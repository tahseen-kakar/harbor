import Foundation

struct DownloadDestinationResolver {
    nonisolated(unsafe) private let fileManager: FileManager

    nonisolated init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    nonisolated func resolvedFilename(
        custom: String?,
        responseSuggestedFilename: String?,
        sourceURL: URL
    ) -> String {
        let trimmedCustom = custom?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let trimmedSuggested = responseSuggestedFilename?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        var candidate = trimmedCustom
            ?? trimmedSuggested
            ?? sourceURL.lastPathComponent.nilIfEmpty
            ?? sourceURL.host
            ?? "Download"

        if let trimmedCustom,
           URL(fileURLWithPath: trimmedCustom).pathExtension.isEmpty {
            let extensionSource = URL(fileURLWithPath: trimmedSuggested ?? "").pathExtension.nilIfEmpty
                ?? sourceURL.pathExtension.nilIfEmpty

            if let extensionSource {
                candidate += ".\(extensionSource)"
            }
        }

        return sanitize(candidate)
    }

    nonisolated func uniqueDestinationURL(for filename: String, in directory: URL) -> URL {
        let cleanName = sanitize(filename)
        let baseURL = directory.appendingPathComponent(cleanName)

        guard fileManager.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        let fileExtension = baseURL.pathExtension
        let baseName = fileExtension.isEmpty
            ? cleanName
            : String(cleanName.dropLast(fileExtension.count + 1))

        var attempt = 2
        while true {
            let candidateName: String
            if fileExtension.isEmpty {
                candidateName = "\(baseName) \(attempt)"
            } else {
                candidateName = "\(baseName) \(attempt).\(fileExtension)"
            }

            let candidateURL = directory.appendingPathComponent(candidateName)
            if fileManager.fileExists(atPath: candidateURL.path) == false {
                return candidateURL
            }

            attempt += 1
        }
    }

    nonisolated func moveDownloadedFile(
        from temporaryURL: URL,
        customFilename: String?,
        responseSuggestedFilename: String?,
        sourceURL: URL,
        into directory: URL
    ) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let targetName = resolvedFilename(
            custom: customFilename,
            responseSuggestedFilename: responseSuggestedFilename,
            sourceURL: sourceURL
        )
        let destinationURL = uniqueDestinationURL(for: targetName, in: directory)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    private nonisolated func sanitize(_ filename: String) -> String {
        let replaced = filename
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return replaced.isEmpty ? "Download" : replaced
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
