import AppKit

@MainActor
final class HarborAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        let didHandle = ExternalTorrentOpenCoordinator.shared.receive(urls: urls)

        sender.reply(toOpenOrPrint: didHandle ? .success : .failure)
    }
}
