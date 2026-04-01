import AppKit
import Foundation

@MainActor
final class ExternalTorrentOpenCoordinator {
    static let shared = ExternalTorrentOpenCoordinator()

    private var pendingURLs: [URL] = []
    private var handler: (([URL]) -> Void)?

    private init() {}

    @discardableResult
    func receive(urls: [URL]) -> Bool {
        let torrentURLs = urls.filter { DownloadSourceKind.detect(from: $0) == .torrentFile }
        guard torrentURLs.isEmpty == false else {
            return false
        }

        pendingURLs.append(contentsOf: torrentURLs)
        bringHarborToFront()
        drainPendingURLsIfNeeded()
        return true
    }

    func installHandler(_ handler: @escaping ([URL]) -> Void) {
        self.handler = handler
        drainPendingURLsIfNeeded()
    }

    private func drainPendingURLsIfNeeded() {
        guard let handler, pendingURLs.isEmpty == false else {
            return
        }

        let urls = pendingURLs
        pendingURLs.removeAll()
        handler(urls)
    }

    private func bringHarborToFront() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) ?? NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
