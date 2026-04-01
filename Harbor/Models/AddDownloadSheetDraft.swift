import Foundation

enum AddDownloadEntryMode: String, CaseIterable, Identifiable, Sendable {
    case linkOrMagnet
    case torrentFile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .linkOrMagnet:
            "Link or Magnet"
        case .torrentFile:
            "Torrent File"
        }
    }
}

struct AddDownloadSheetDraft: Identifiable, Sendable {
    let id: UUID
    let entryMode: AddDownloadEntryMode
    let sourceURLText: String
    let customFilename: String
    let torrentFileURL: URL?
    let destinationFolderURL: URL
    let shouldStartImmediately: Bool

    init(
        id: UUID = UUID(),
        entryMode: AddDownloadEntryMode,
        sourceURLText: String = "",
        customFilename: String = "",
        torrentFileURL: URL? = nil,
        destinationFolderURL: URL,
        shouldStartImmediately: Bool
    ) {
        self.id = id
        self.entryMode = entryMode
        self.sourceURLText = sourceURLText
        self.customFilename = customFilename
        self.torrentFileURL = torrentFileURL
        self.destinationFolderURL = destinationFolderURL
        self.shouldStartImmediately = shouldStartImmediately
    }

    static func blank(
        destinationFolderURL: URL,
        shouldStartImmediately: Bool
    ) -> AddDownloadSheetDraft {
        AddDownloadSheetDraft(
            entryMode: .linkOrMagnet,
            destinationFolderURL: destinationFolderURL,
            shouldStartImmediately: shouldStartImmediately
        )
    }

    static func torrentFile(
        _ fileURL: URL,
        destinationFolderURL: URL,
        shouldStartImmediately: Bool
    ) -> AddDownloadSheetDraft {
        AddDownloadSheetDraft(
            entryMode: .torrentFile,
            torrentFileURL: fileURL,
            destinationFolderURL: destinationFolderURL,
            shouldStartImmediately: shouldStartImmediately
        )
    }
}
