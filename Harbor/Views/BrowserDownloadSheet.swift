import SwiftUI
import WebKit

struct BrowserDownloadSheet: View {
    let center: DownloadCenter
    let session: BrowserDownloadSession

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            BrowserSessionWebView(webView: session.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footer
        }
        .frame(minWidth: 760, idealWidth: 960, minHeight: 560, idealHeight: 680)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Continue in Harbor")
                        .font(.title3.weight(.semibold))

                    Text(session.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if session.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let currentURL = session.currentURL {
                Text(currentURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.pageTitle ?? session.displayName)
                    .font(.subheadline.weight(.medium))
                Text("Close this sheet any time to keep the download waiting for another browser session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cancel") {
                center.dismissBrowserSession()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct BrowserSessionWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
