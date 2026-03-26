import Foundation
import Observation
import WebKit

enum BrowserDownloadEvent {
    case started(
        id: UUID,
        suggestedFilename: String?,
        expectedBytes: Int64,
        responseMimeType: String?,
        statusCode: Int?
    )
    case finished(
        id: UUID,
        temporaryURL: URL,
        suggestedFilename: String?,
        responseMimeType: String?,
        statusCode: Int?,
        expectedBytes: Int64
    )
    case failed(id: UUID, message: String)
}

@MainActor
@Observable
final class BrowserDownloadSession: Identifiable {
    let id = UUID()
    let downloadID: UUID
    let sourceURL: URL
    let displayName: String

    @ObservationIgnored let webView: WKWebView

    var currentURL: URL?
    var pageTitle: String?
    var statusMessage = "Complete any required sign-in or verification. Harbor will capture the file automatically."
    var isLoading = true

    fileprivate var hasStartedDownload = false

    init(downloadID: UUID, sourceURL: URL, displayName: String, webView: WKWebView) {
        self.downloadID = downloadID
        self.sourceURL = sourceURL
        self.displayName = displayName
        self.webView = webView
        self.currentURL = sourceURL
    }
}

@MainActor
final class BrowserDownloadCoordinator: NSObject {
    private struct DownloadContext {
        let downloadID: UUID
        let sourceURL: URL
        var suggestedFilename: String?
        var responseMimeType: String?
        var statusCode: Int?
        var expectedBytes: Int64
        var temporaryURL: URL?
    }

    private let destinationResolver: DownloadDestinationResolver
    private let fileManager: FileManager
    private let temporaryDirectory: URL
    private let onEvent: (BrowserDownloadEvent) -> Void

    private var activeSession: BrowserDownloadSession?
    private var downloadContexts: [ObjectIdentifier: DownloadContext] = [:]

    init(
        destinationResolver: DownloadDestinationResolver = DownloadDestinationResolver(),
        fileManager: FileManager = .default,
        onEvent: @escaping (BrowserDownloadEvent) -> Void
    ) {
        self.destinationResolver = destinationResolver
        self.fileManager = fileManager
        self.temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("HarborBrowserDownloads", isDirectory: true)
        self.onEvent = onEvent

        super.init()

        try? fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    func startSession(
        downloadID: UUID,
        sourceURL: URL,
        displayName: String
    ) -> BrowserDownloadSession {
        if let activeSession, activeSession.downloadID == downloadID {
            return activeSession
        }

        cancelSession()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self

        let session = BrowserDownloadSession(
            downloadID: downloadID,
            sourceURL: sourceURL,
            displayName: displayName,
            webView: webView
        )

        activeSession = session
        webView.load(URLRequest(url: sourceURL))
        return session
    }

    func cancelSession() {
        activeSession?.webView.stopLoading()
        activeSession = nil
    }

    private func track(download: WKDownload) {
        guard let activeSession else {
            return
        }

        activeSession.hasStartedDownload = true
        activeSession.statusMessage = "Starting secure browser-backed download…"

        downloadContexts[ObjectIdentifier(download)] = DownloadContext(
            downloadID: activeSession.downloadID,
            sourceURL: activeSession.sourceURL,
            suggestedFilename: nil,
            responseMimeType: nil,
            statusCode: nil,
            expectedBytes: 0,
            temporaryURL: nil
        )

        download.delegate = self
    }

    private func shouldDownloadInBrowser(response: URLResponse, isForMainFrame: Bool) -> Bool {
        guard isForMainFrame else {
            return false
        }

        let normalizedMimeType = response.mimeType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return isHTMLMimeType(normalizedMimeType) == false
    }

    private func isHTMLMimeType(_ mimeType: String?) -> Bool {
        mimeType == "text/html" || mimeType == "application/xhtml+xml"
    }

    private func shouldIgnoreNavigationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let frameLoadInterruptedByPolicyChange = 102

        if nsError.domain == WKErrorDomain,
           nsError.code == frameLoadInterruptedByPolicyChange {
            return true
        }

        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled {
            return true
        }

        return false
    }

    private func temporaryDownloadURL(
        suggestedFilename: String?,
        sourceURL: URL
    ) throws -> URL {
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let filename = destinationResolver.resolvedFilename(
            custom: nil,
            responseSuggestedFilename: suggestedFilename,
            sourceURL: sourceURL
        )

        return temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(filename)")
    }

    private func refreshSessionURL(from webView: WKWebView) {
        if let url = webView.url {
            activeSession?.currentURL = url
        }
    }

    private func completeNavigationFailure(_ error: Error) {
        guard let activeSession else {
            return
        }

        if shouldIgnoreNavigationError(error) || activeSession.hasStartedDownload {
            return
        }

        let downloadID = activeSession.downloadID
        self.activeSession = nil
        onEvent(.failed(id: downloadID, message: error.localizedDescription))
    }
}

extension BrowserDownloadCoordinator: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard let activeSession else {
            decisionHandler(.cancel)
            return
        }

        activeSession.currentURL = navigationResponse.response.url ?? activeSession.currentURL

        if shouldDownloadInBrowser(
            response: navigationResponse.response,
            isForMainFrame: navigationResponse.isForMainFrame
        ) {
            decisionHandler(.download)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        activeSession?.isLoading = true
        refreshSessionURL(from: webView)
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        refreshSessionURL(from: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        refreshSessionURL(from: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activeSession?.isLoading = false
        activeSession?.pageTitle = webView.title
        refreshSessionURL(from: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completeNavigationFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        completeNavigationFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        track(download: download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        track(download: download)
    }
}

extension BrowserDownloadCoordinator: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let key = ObjectIdentifier(download)

        guard var context = downloadContexts[key] else {
            completionHandler(nil)
            return
        }

        do {
            let temporaryURL = try temporaryDownloadURL(
                suggestedFilename: suggestedFilename,
                sourceURL: context.sourceURL
            )

            context.suggestedFilename = suggestedFilename
            context.responseMimeType = response.mimeType
            context.statusCode = (response as? HTTPURLResponse)?.statusCode
            context.expectedBytes = max(response.expectedContentLength, 0)
            context.temporaryURL = temporaryURL
            downloadContexts[key] = context

            completionHandler(temporaryURL)

            activeSession = nil
            onEvent(
                .started(
                    id: context.downloadID,
                    suggestedFilename: suggestedFilename,
                    expectedBytes: context.expectedBytes,
                    responseMimeType: context.responseMimeType,
                    statusCode: context.statusCode
                )
            )
        } catch {
            completionHandler(nil)
            activeSession = nil
            downloadContexts.removeValue(forKey: key)
            onEvent(.failed(id: context.downloadID, message: error.localizedDescription))
        }
    }

    func download(
        _ download: WKDownload,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }

    func download(
        _ download: WKDownload,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)

        guard let context = downloadContexts.removeValue(forKey: key),
              let temporaryURL = context.temporaryURL
        else {
            return
        }

        onEvent(
            .finished(
                id: context.downloadID,
                temporaryURL: temporaryURL,
                suggestedFilename: context.suggestedFilename,
                responseMimeType: context.responseMimeType,
                statusCode: context.statusCode,
                expectedBytes: context.expectedBytes
            )
        )
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let key = ObjectIdentifier(download)
        let context = downloadContexts.removeValue(forKey: key)

        if let temporaryURL = context?.temporaryURL {
            try? fileManager.removeItem(at: temporaryURL)
        }

        if let downloadID = context?.downloadID {
            onEvent(.failed(id: downloadID, message: error.localizedDescription))
        }
    }
}

extension BrowserDownloadCoordinator: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }

        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        cancelSession()
    }
}
