import AppKit
import Foundation
import UniformTypeIdentifiers

enum TorrentFileSelectionService {
    @MainActor
    static func chooseTorrentFile(startingAt url: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = url
        panel.prompt = "Choose Torrent"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "torrent") ?? .data
        ]

        return panel.runModal() == .OK ? panel.url : nil
    }
}
