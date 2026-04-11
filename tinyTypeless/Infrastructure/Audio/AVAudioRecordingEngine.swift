import AVFoundation
import Foundation

final class AVAudioRecordingEngine: NSObject, RecordingEngine, AVAudioRecorderDelegate, @unchecked Sendable {
    private enum RecordingConstants {
        static let sampleRate = 16_000
        static let channelCount = 1
        static let fileExtension = "wav"
        static let meterFloorDb: Float = -52
        static let meterInterval: TimeInterval = 0.05
        static let visualizationBars = 5
        static let visualizationSilenceThreshold: Float = 0.018
    }

    private let prewarmer: AudioSessionPrewarmer
    private let fileWriter: TemporaryAudioFileWriter
    private let callbackQueue = DispatchQueue.main
    private let analysisQueue = DispatchQueue(label: "tinyTypeless.audio.visualization")

    weak var levelObserver: RecordingLevelObserving?
    weak var chunkObserver: RecordingChunkObserving?

    private var recorder: AVAudioRecorder?
    private var visualizationEngine: AVAudioEngine?
    private var recordingStartedAt: Date?
    private var recordingFileURL: URL?
    private var meterTimer: DispatchSourceTimer?
    private var smoothedBarLevels = Array(repeating: Float(0.2), count: RecordingConstants.visualizationBars)

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

        guard recorder == nil else {
            throw DictationError.recordingFailed("已经存在进行中的录音。")
        }

        let fileURL = try fileWriter.makeTemporaryAudioFileURL(
            fileExtension: RecordingConstants.fileExtension
        )

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: RecordingConstants.sampleRate,
            AVNumberOfChannelsKey: RecordingConstants.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true

        guard recorder.prepareToRecord(), recorder.record() else {
            throw DictationError.recordingFailed("无法启动录音。")
        }

        self.recorder = recorder
        self.recordingFileURL = fileURL
        self.recordingStartedAt = Date()

        startVisualizationTap()
        startMetering()
        publishLevel(0)
    }

    func stopRecording() async throws -> AudioPayload {
        guard let recorder, let recordingFileURL else {
            throw DictationError.recordingFailed("当前没有可结束的录音。")
        }

        recorder.stop()
        stopVisualizationTap()
        stopMetering()

        let durationMs = max(
            Int((Date().timeIntervalSince(recordingStartedAt ?? Date())) * 1000),
            0
        )

        cleanupAfterStop()
        publishLevel(0)

        return AudioPayload(
            fileURL: recordingFileURL,
            format: RecordingConstants.fileExtension,
            sampleRate: RecordingConstants.sampleRate,
            durationMs: durationMs
        )
    }

    private func startMetering() {
        stopMetering()

        let timer = DispatchSource.makeTimerSource(queue: callbackQueue)
        timer.schedule(deadline: .now(), repeating: RecordingConstants.meterInterval)
        timer.setEventHandler { [weak self] in
            guard let self, let recorder = self.recorder, recorder.isRecording else {
                return
            }

            recorder.updateMeters()
            let averagePower = recorder.averagePower(forChannel: 0)
            let peakPower = recorder.peakPower(forChannel: 0)
            let averageLevel = self.normalizedLevel(from: averagePower)
            let peakLevel = self.normalizedLevel(from: peakPower)
            let level = min(max((averageLevel * 0.45) + (peakLevel * 0.78), 0), 1)
            self.levelObserver?.recordingLevelDidUpdate(normalizedLevel: level)
        }
        meterTimer = timer
        timer.resume()
    }

    private func stopMetering() {
        meterTimer?.setEventHandler {}
        meterTimer?.cancel()
        meterTimer = nil
    }

    private func cleanupAfterStop() {
        recorder = nil
        recordingStartedAt = nil
        recordingFileURL = nil
    }

    private func startVisualizationTap() {
        stopVisualizationTap()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.analysisQueue.async {
                self?.processVisualizationBuffer(buffer)
            }
        }

        do {
            engine.prepare()
            try engine.start()
            visualizationEngine = engine
        } catch {
            inputNode.removeTap(onBus: 0)
            visualizationEngine = nil
        }
    }

    private func stopVisualizationTap() {
        guard let visualizationEngine else {
            smoothedBarLevels = Array(repeating: 0.2, count: RecordingConstants.visualizationBars)
            return
        }

        visualizationEngine.inputNode.removeTap(onBus: 0)
        visualizationEngine.stop()
        self.visualizationEngine = nil
        smoothedBarLevels = Array(repeating: 0.2, count: RecordingConstants.visualizationBars)
        publishVisualization(barLevels: Array(repeating: 0, count: RecordingConstants.visualizationBars), level: 0)
    }

    private func normalizedLevel(from averagePower: Float) -> Float {
        let db = max(averagePower, RecordingConstants.meterFloorDb)
        let linear = (db - RecordingConstants.meterFloorDb) / abs(RecordingConstants.meterFloorDb)
        return min(max(powf(linear, 1.4), 0), 1)
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

    private func processVisualizationBuffer(_ buffer: AVAudioPCMBuffer) {
        let samples = extractSamples(from: buffer)
        guard !samples.isEmpty else {
            return
        }

        let rawBars = analyzedBarLevels(from: samples)
        let peak = rawBars.max() ?? 0

        guard peak >= RecordingConstants.visualizationSilenceThreshold else {
            smoothedBarLevels = Array(repeating: 0.2, count: RecordingConstants.visualizationBars)
            publishVisualization(barLevels: Array(repeating: 0, count: RecordingConstants.visualizationBars), level: 0)
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

    private func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return []
        }

        if let channelData = buffer.floatChannelData {
            let primaryChannel = channelData[0]
            return Array(UnsafeBufferPointer(start: primaryChannel, count: frameCount))
        }

        if let channelData = buffer.int16ChannelData {
            let primaryChannel = channelData[0]
            return Array(UnsafeBufferPointer(start: primaryChannel, count: frameCount)).map {
                Float($0) / Float(Int16.max)
            }
        }

        return []
    }
}
