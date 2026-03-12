import SwiftUI

struct DownloadCommands: Commands {
    let center: DownloadCenter

    var body: some Commands {
        SidebarCommands()

        CommandMenu("Downloads") {
            Button("New Download...") {
                center.presentAddSheet()
            }
            .keyboardShortcut("n")

            Divider()

            Button("Pause or Resume Selected") {
                center.togglePauseResumeForSelection()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Retry Selected") {
                center.retrySelectedDownload()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Cancel Selected") {
                center.cancelSelectedDownload()
            }

            Divider()

            Button("Pause All") {
                center.pauseAll()
            }

            Button("Resume All") {
                center.resumeAll()
            }

            Divider()

            Button("Reveal in Finder") {
                center.revealSelectedInFinder()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

            Button("Open Downloaded File") {
                center.openSelectedDownload()
            }
            .keyboardShortcut(.return, modifiers: [.command])

            Divider()

            Button("Remove Selected from List") {
                center.removeSelectedDownload()
            }

            Button("Clear Completed") {
                center.clearCompleted()
            }

            Button("Clear Failed") {
                center.clearFailed()
            }
        }
    }
}
