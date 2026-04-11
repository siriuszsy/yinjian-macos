import Foundation

final class TemporaryAudioFileWriter {
    private let paths: FileSystemPaths

    init(paths: FileSystemPaths) {
        self.paths = paths
    }

    func makeTemporaryAudioFileURL(fileExtension: String) throws -> URL {
        try paths.ensureDirectoriesExist()

        return paths.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
    }
}
