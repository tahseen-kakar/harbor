import Foundation

struct TorrentContentsPreviewService: Sendable {
    func preview(
        sourceKind: DownloadSourceKind,
        sourceURL: URL,
        requestHeaders: [RequestHeader],
        torrentService: Aria2TorrentService
    ) async throws -> TorrentContentsPreview {
        let data: Data
        switch sourceKind {
        case .magnetLink:
            data = try await torrentService.previewMagnetMetainfo(
                at: sourceURL,
                requestHeaders: requestHeaders
            )
        case .torrentFile:
            if sourceURL.isFileURL {
                data = try readLocalTorrent(at: sourceURL)
            } else {
                data = try await TorrentSourceLoader.fetch(
                    from: sourceURL,
                    requestHeaders: requestHeaders
                )
            }
        case .directURL, .mediaURL:
            throw TorrentEngineError.invalidSource
        }

        return try TorrentMetainfoParser.preview(from: data)
    }

    private func readLocalTorrent(at sourceURL: URL) throws -> Data {
        let didAccessSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        return try ManagedTorrentSourceStore.loadTorrentData(at: sourceURL)
    }
}
