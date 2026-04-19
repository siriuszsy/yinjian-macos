@preconcurrency import AVFoundation
import Foundation

final class AVAudioRecordingEngine: NSObject, RecordingEngine, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private enum RecordingConstants {
        static let sampleRate = 16_000
        static let channelCount = 1
        static let fileExtension = "wav"
        static let bitDepth = 16
        static let bytesPerSample = 2
        static let meterFloorDb: Float = -52
        static let visualizationBars = 5
        static let visualizationSilenceThreshold: Float = 0.018
        static let liveChunkDurationMs = 40
        static let liveChunkByteCount = (sampleRate * liveChunkDurationMs / 1000) * channelCount * bytesPerSample
        static func captureAudioSettings() -> [String: Any] {
            [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVLinearPCMBitDepthKey: bitDepth,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        }
    }

    private let prewarmer: AudioSessionPrewarmer
    private let fileWriter: TemporaryAudioFileWriter
    private let callbackQueue = DispatchQueue.main
    private let captureQueue = DispatchQueue(label: "tinyTypeless.audio.capture")

    weak var levelObserver: RecordingLevelObserving?
    weak var chunkObserver: RecordingChunkObserving?

    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var audioInput: AVCaptureDeviceInput?
    private var waveRecorder: PCMWaveFileRecorder?
    private var recordingStartedAt: Date?
    private var recordingFileURL: URL?
    private var recordingError: Error?
    private var smoothedBarLevels = Array(repeating: Float(0.2), count: RecordingConstants.visualizationBars)
    private var pendingStreamingPCMData = Data()

    init(
        prewarmer: AudioSessionPrewarmer,
        fileWriter: TemporaryAudioFileWriter
    ) {
        self.prewarmer = prewarmer
        self.fileWriter = fileWriter
    }

    func prepare() async throws {
        try await prewarmer.prepare()
    }

    func startRecording() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw DictationError.microphonePermissionDenied
        }

        guard captureSession == nil else {
            throw DictationError.recordingFailed("已经存在进行中的录音。")
        }

        let fileURL = try fileWriter.makeTemporaryAudioFileURL(
            fileExtension: RecordingConstants.fileExtension
        )
        let waveRecorder = try PCMWaveFileRecorder(
            fileURL: fileURL,
            sampleRate: RecordingConstants.sampleRate,
            channelCount: RecordingConstants.channelCount,
            bitDepth: RecordingConstants.bitDepth
        )

        do {
            try captureQueue.sync {
                pendingStreamingPCMData.removeAll(keepingCapacity: true)
                smoothedBarLevels = Array(repeating: 0.2, count: RecordingConstants.visualizationBars)
                recordingError = nil
                recordingStartedAt = Date()
                recordingFileURL = fileURL
                self.waveRecorder = waveRecorder

                let session = try makeCaptureSession()
                captureSession = session
                session.startRunning()

                guard session.isRunning else {
                    throw DictationError.recordingFailed("无法启动录音。")
                }
            }
        } catch {
            captureQueue.sync {
                audioOutput?.setSampleBufferDelegate(nil, queue: nil)
                captureSession?.stopRunning()
                cleanupAfterStop(closeRecorder: true)
            }
            throw error
        }

        publishLevel(0)
    }

    func stopRecording() async throws -> AudioPayload {
        let fileURL: URL
        let durationMs: Int
        let pendingError: Error?

        do {
            (fileURL, durationMs, pendingError) = try captureQueue.sync {
                guard let captureSession,
                      let recordingFileURL else {
                    throw DictationError.recordingFailed("当前没有可结束的录音。")
                }

                audioOutput?.setSampleBufferDelegate(nil, queue: nil)
                captureSession.stopRunning()
                flushPendingStreamingChunk()

                let durationMs = max(
                    Int((Date().timeIntervalSince(recordingStartedAt ?? Date())) * 1000),
                    0
                )
                let pendingError = recordingError

                try waveRecorder?.finish()
                cleanupAfterStop(closeRecorder: false)
                return (recordingFileURL, durationMs, pendingError)
            }
        } catch {
            throw error
        }

        publishLevel(0)
        publishVisualization(
            barLevels: Array(repeating: 0, count: RecordingConstants.visualizationBars),
            level: 0
        )

        if let pendingError {
            throw pendingError
        }

        return AudioPayload(
            fileURL: fileURL,
            format: RecordingConstants.fileExtension,
            sampleRate: RecordingConstants.sampleRate,
            durationMs: durationMs
        )
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        _ = output
        _ = connection

        guard recordingError == nil else {
            return
        }

        do {
            let pcmData = try extractPCMData(from: sampleBuffer)
            guard !pcmData.isEmpty else {
                return
            }

            try waveRecorder?.append(pcmData)
            processVisualizationData(pcmData)
            processStreamingData(pcmData)
        } catch {
            if recordingError == nil {
                recordingError = error
            }
        }
    }

    private func makeCaptureSession() throws -> AVCaptureSession {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw DictationError.recordingFailed("当前没有可用的麦克风输入设备。")
        }

        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = RecordingConstants.captureAudioSettings()
        output.setSampleBufferDelegate(self, queue: captureQueue)

        let session = AVCaptureSession()
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canAddInput(input) else {
            throw DictationError.recordingFailed("无法连接麦克风输入。")
        }
        session.addInput(input)

        guard session.canAddOutput(output) else {
            throw DictationError.recordingFailed("无法创建音频采集输出。")
        }
        session.addOutput(output)

        audioInput = input
        audioOutput = output
        return session
    }

    private func extractPCMData(from sampleBuffer: CMSampleBuffer) throws -> Data {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            throw DictationError.recordingFailed("无法读取音频格式描述。")
        }

        let asbd = asbdPointer.pointee
        guard Int(asbd.mSampleRate) == RecordingConstants.sampleRate,
              Int(asbd.mChannelsPerFrame) == RecordingConstants.channelCount else {
            throw DictationError.recordingFailed("音频输入格式与当前实时识别要求不一致。")
        }

        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            throw DictationError.recordingFailed("无法读取音频数据块。")
        }

        let byteCount = CMBlockBufferGetDataLength(dataBuffer)
        guard byteCount > 0 else {
            return Data()
        }

        var data = Data(count: byteCount)
        let status = data.withUnsafeMutableBytes { destination in
            guard let baseAddress = destination.baseAddress else {
                return kCMBlockBufferBadPointerParameterErr
            }

            return CMBlockBufferCopyDataBytes(
                dataBuffer,
                atOffset: 0,
                dataLength: byteCount,
                destination: baseAddress
            )
        }

        guard status == noErr else {
            throw DictationError.recordingFailed("音频数据复制失败。")
        }

        return data
    }

    private func processVisualizationData(_ pcmData: Data) {
        let samples = normalizedSamples(from: pcmData)
        guard !samples.isEmpty else {
            return
        }

        let rawBars = analyzedBarLevels(from: samples)
        let peak = rawBars.max() ?? 0

        guard peak >= RecordingConstants.visualizationSilenceThreshold else {
            smoothedBarLevels = Array(repeating: 0.2, count: RecordingConstants.visualizationBars)
            publishVisualization(
                barLevels: Array(repeating: 0, count: RecordingConstants.visualizationBars),
                level: 0
            )
            publishLevel(0)
            return
        }

        var nextBars = smoothedBarLevels
        for index in nextBars.indices {
            let target = min(max(powf(rawBars[index] * 3.6, 0.72), 0.08), 1)
            let current = smoothedBarLevels[index]
            let smoothing: Float = target > current ? 0.82 : 0.26
            nextBars[index] = current + ((target - current) * smoothing)
        }

        smoothedBarLevels = nextBars
        let normalizedLevel = min(max(powf(peak * 3.2, 0.7), 0), 1)
        publishVisualization(barLevels: nextBars, level: normalizedLevel)
        publishLevel(normalizedLevel)
    }

    private func normalizedSamples(from pcmData: Data) -> [Float] {
        guard !pcmData.isEmpty else {
            return []
        }

        return pcmData.withUnsafeBytes { rawBuffer -> [Float] in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            return samples.map { sample in
                Float(sample) / Float(Int16.max)
            }
        }
    }

    private func analyzedBarLevels(from samples: [Float]) -> [Float] {
        let barCount = RecordingConstants.visualizationBars
        let segmentSize = max(samples.count / barCount, 1)
        var bars = Array(repeating: Float(0), count: barCount)

        for index in 0..<barCount {
            let start = index * segmentSize
            let end = min(start + segmentSize, samples.count)
            guard start < end else {
                continue
            }

            var peak: Float = 0
            for sample in samples[start..<end] {
                peak = max(peak, abs(sample))
            }
            bars[index] = peak
        }

        return bars
    }

    private func processStreamingData(_ pcmData: Data) {
        pendingStreamingPCMData.append(pcmData)

        while pendingStreamingPCMData.count >= RecordingConstants.liveChunkByteCount {
            let chunkData = pendingStreamingPCMData.prefix(RecordingConstants.liveChunkByteCount)
            publishAudioChunk(Data(chunkData))
            pendingStreamingPCMData.removeFirst(RecordingConstants.liveChunkByteCount)
        }
    }

    private func flushPendingStreamingChunk() {
        guard !pendingStreamingPCMData.isEmpty else {
            return
        }

        publishAudioChunk(pendingStreamingPCMData)
        pendingStreamingPCMData.removeAll(keepingCapacity: true)
    }

    private func publishAudioChunk(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        let chunk = AudioChunk(
            data: data,
            sampleRate: RecordingConstants.sampleRate,
            channelCount: RecordingConstants.channelCount
        )
        chunkObserver?.recordingDidProduceAudioChunk(chunk)
    }

    private func cleanupAfterStop(closeRecorder: Bool) {
        if closeRecorder {
            try? waveRecorder?.finish()
        }

        captureSession = nil
        audioOutput = nil
        audioInput = nil
        waveRecorder = nil
        recordingStartedAt = nil
        recordingFileURL = nil
        recordingError = nil
        pendingStreamingPCMData.removeAll(keepingCapacity: false)
        smoothedBarLevels = Array(repeating: 0.2, count: RecordingConstants.visualizationBars)
    }

    private func publishLevel(_ level: Float) {
        callbackQueue.async { [weak self] in
            self?.levelObserver?.recordingLevelDidUpdate(normalizedLevel: level)
        }
    }

    private func publishVisualization(barLevels: [Float], level: Float) {
        callbackQueue.async { [weak self] in
            self?.levelObserver?.recordingVisualizationDidUpdate(
                barLevels: barLevels,
                normalizedLevel: level
            )
        }
    }
}
