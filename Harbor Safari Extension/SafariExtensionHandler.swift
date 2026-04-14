import AppKit
import SafariServices
import os

final class SafariExtensionHandler: SFSafariExtensionHandler {
    private static let addLinkCommand = "addLinkToHarbor"
    private static let linkUserInfoKey = "linkHref"
    private static let logger = Logger(
        subsystem: "co.hapy.harbor.SafariExtension",
        category: "SafariExtension"
    )

    override func toolbarItemClicked(in window: SFSafariWindow) {
        window.getActiveTab { tab in
            tab?.getActivePage { page in
                page?.getPropertiesWithCompletionHandler { properties in
                    guard let sourceURL = properties?.url,
                          Self.isSupportedSourceURL(sourceURL)
                    else {
                        return
                    }

                    Self.openInHarbor(sourceURL)
                }
            }
        }
    }

    override func validateToolbarItem(
        in window: SFSafariWindow,
        validationHandler: @escaping ((Bool, String) -> Void)
    ) {
        window.getActiveTab { tab in
            guard let tab else {
                validationHandler(false, "")
                return
            }

            tab.getActivePage { page in
                guard let page else {
                    validationHandler(false, "")
                    return
                }

                page.getPropertiesWithCompletionHandler { properties in
                    let isSupported = properties?.url.map(Self.isSupportedSourceURL) ?? false
                    validationHandler(isSupported, "")
                }
            }
        }
    }

    override func contextMenuItemSelected(
        withCommand command: String,
        in page: SFSafariPage,
        userInfo: [String: Any]?
    ) {
        guard command == Self.addLinkCommand,
              let sourceURL = Self.sourceURL(from: userInfo)
        else {
            return
        }

        Self.openInHarbor(sourceURL)
    }

    override func validateContextMenuItem(
        withCommand command: String,
        in page: SFSafariPage,
        userInfo: [String: Any]?,
        validationHandler: @escaping ((Bool, String?) -> Void)
    ) {
        guard command == Self.addLinkCommand,
              Self.sourceURL(from: userInfo) != nil
        else {
            validationHandler(true, nil)
            return
        }

        validationHandler(false, "Add Link to Harbor")
    }

    private static func sourceURL(from userInfo: [String: Any]?) -> URL? {
        guard let link = userInfo?[linkUserInfoKey] as? String,
              let sourceURL = URL(string: link),
              isSupportedSourceURL(sourceURL)
        else {
            return nil
        }

        return sourceURL
    }

    private static func isSupportedSourceURL(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "http", "https", "magnet":
            true
        default:
            false
        }
    }

    private static func openInHarbor(_ sourceURL: URL) {
        guard let harborURL = harborAddURL(for: sourceURL) else {
            return
        }

        if NSWorkspace.shared.open(harborURL) == false {
            logger.error("Failed to open Harbor URL: \(harborURL.absoluteString, privacy: .public)")
        }
    }

    private static func harborAddURL(for sourceURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "harbor"
        components.host = "add"
        components.queryItems = [
            URLQueryItem(name: "url", value: sourceURL.absoluteString)
        ]

        return components.url
    }
}
