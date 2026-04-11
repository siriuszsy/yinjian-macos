import Foundation

protocol RecordingLevelObserving: AnyObject {
    func recordingLevelDidUpdate(normalizedLevel: Float)
    func recordingVisualizationDidUpdate(barLevels: [Float], normalizedLevel: Float)
}

protocol RecordingChunkObserving: AnyObject {
    func recordingDidProduceAudioChunk(_ chunk: AudioChunk)
}

protocol RecordingEngine {
    var levelObserver: RecordingLevelObserving? { get set }
    var chunkObserver: RecordingChunkObserving? { get set }
    func prepare() async throws
    func startRecording() throws
    func stopRecording() async throws -> AudioPayload
}
