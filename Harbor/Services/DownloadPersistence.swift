import Foundation

actor DownloadPersistence {
    private let fileManager: FileManager
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let applicationSupportURL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)

        let directoryURL = applicationSupportURL.appendingPathComponent("Harbor", isDirectory: true)
        self.fileURL = directoryURL.appendingPathComponent("downloads.json")
    }

    func load() throws -> [DownloadRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([DownloadRecord].self, from: data)
    }

    func save(_ records: [DownloadRecord]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(records)
        try data.write(to: fileURL, options: [.atomic])
    }
}
