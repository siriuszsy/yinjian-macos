import Foundation

final class JSONLSessionLogStore: SessionLogStore {
    private let paths: FileSystemPaths
    private let encoder = JSONEncoder()

    init(paths: FileSystemPaths) {
        self.paths = paths
        encoder.dateEncodingStrategy = .iso8601
    }

    func append(_ record: SessionRecord) async {
        do {
            try paths.ensureDirectoriesExist()
            let data = try encoder.encode(record)
            let line = data + Data([0x0A])

            if FileManager.default.fileExists(atPath: paths.sessionsLogURL.path) {
                let handle = try FileHandle(forWritingTo: paths.sessionsLogURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: paths.sessionsLogURL, options: .atomic)
            }
        } catch {
            // TODO: Wire up OSLog once logging infrastructure is live.
        }
    }
}
