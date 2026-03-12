import Foundation

struct AddDownloadRequest: Sendable {
    let sourceKind: DownloadSourceKind
    let sourceURL: URL
    let customFilename: String?
    let destinationFolder: URL
    let shouldStartImmediately: Bool
}
