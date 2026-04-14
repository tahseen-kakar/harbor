import AppKit
import Foundation

enum ExternalDownloadOpenRequest: Sendable {
    case torrentFile(URL)
    case sourceURL(URL)
}

@MainActor
final class ExternalDownloadOpenCoordinator {
    static let shared = ExternalDownloadOpenCoordinator()

    private var pendingRequests: [ExternalDownloadOpenRequest] = []
    private var handler: (([ExternalDownloadOpenRequest]) -> Void)?

    private init() {}

    @discardableResult
    func receive(urls: [URL]) -> Bool {
        let requests = urls.compactMap(Self.openRequest(from:))
        guard requests.isEmpty == false else {
            return false
        }

        pendingRequests.append(contentsOf: requests)
        bringHarborToFront()
        drainPendingRequestsIfNeeded()
        return true
    }

    func installHandler(_ handler: @escaping ([ExternalDownloadOpenRequest]) -> Void) {
        self.handler = handler
        drainPendingRequestsIfNeeded()
    }

    private func drainPendingRequestsIfNeeded() {
        guard let handler, pendingRequests.isEmpty == false else {
            return
        }

        let requests = pendingRequests
        pendingRequests.removeAll()
        handler(requests)
    }

    private func bringHarborToFront() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) ?? NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private static func openRequest(from url: URL) -> ExternalDownloadOpenRequest? {
        if DownloadSourceKind.detect(from: url) == .torrentFile {
            return .torrentFile(url)
        }

        guard let sourceURL = sourceURL(fromHarborURL: url),
              let sourceKind = DownloadSourceKind.detect(from: sourceURL),
              sourceKind == .directURL || sourceKind == .magnetLink
        else {
            return nil
        }

        return .sourceURL(sourceURL)
    }

    private static func sourceURL(fromHarborURL url: URL) -> URL? {
        guard url.scheme?.lowercased() == "harbor",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        let command = components.host ?? components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard command == "add" else {
            return nil
        }

        let sourceURLText = components.queryItems?
            .first { $0.name == "url" }?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let sourceURLText, sourceURLText.isEmpty == false else {
            return nil
        }

        return URL(string: sourceURLText)
    }
}
