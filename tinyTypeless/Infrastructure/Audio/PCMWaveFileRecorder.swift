import Foundation

final class PCMWaveFileRecorder {
    private let fileHandle: FileHandle
    private let sampleRate: Int
    private let channelCount: Int
    private let bitDepth: Int
    private var dataByteCount = 0
    private var isFinished = false

    init(
        fileURL: URL,
        sampleRate: Int,
        channelCount: Int,
        bitDepth: Int
    ) throws {
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        self.fileHandle = try FileHandle(forWritingTo: fileURL)
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitDepth = bitDepth
        try fileHandle.write(contentsOf: Data(repeating: 0, count: 44))
    }

    func append(_ pcmData: Data) throws {
        guard !isFinished else {
            return
        }

        guard !pcmData.isEmpty else {
            return
        }

        try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: pcmData)
        dataByteCount += pcmData.count
    }

    func finish() throws {
        guard !isFinished else {
            return
        }

        isFinished = true
        try fileHandle.seek(toOffset: 0)
        try fileHandle.write(contentsOf: waveHeader(dataByteCount: dataByteCount))
        try fileHandle.close()
    }

    private func waveHeader(dataByteCount: Int) -> Data {
        let bytesPerSample = bitDepth / 8
        let byteRate = sampleRate * channelCount * bytesPerSample
        let blockAlign = channelCount * bytesPerSample

        var header = Data()
        header.appendASCII("RIFF")
        header.appendUInt32LE(UInt32(36 + dataByteCount))
        header.appendASCII("WAVE")
        header.appendASCII("fmt ")
        header.appendUInt32LE(16)
        header.appendUInt16LE(1)
        header.appendUInt16LE(UInt16(channelCount))
        header.appendUInt32LE(UInt32(sampleRate))
        header.appendUInt32LE(UInt32(byteRate))
        header.appendUInt16LE(UInt16(blockAlign))
        header.appendUInt16LE(UInt16(bitDepth))
        header.appendASCII("data")
        header.appendUInt32LE(UInt32(dataByteCount))
        return header
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { append(contentsOf: $0) }
    }
}
