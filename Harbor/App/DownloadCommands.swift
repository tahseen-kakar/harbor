import SwiftUI

struct DownloadCommands: Commands {
    let center: DownloadCenter
    let updater: AppUpdater

    var body: some Commands {
        SidebarCommands()

        CommandGroup(after: .appInfo) {
            CheckForUpdatesCommandView(updater: updater)
            Divider()
        }

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
            .disabled(center.canToggleSelectedDownload == false)

            Button("Retry Selected") {
                center.retrySelectedDownload()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(center.canRetrySelectedDownload == false)

            Button("Cancel Selected") {
                center.cancelSelectedDownload()
            }
            .disabled(center.canCancelSelectedDownload == false)

            Divider()

            Button("Pause All") {
                center.pauseAll()
            }
            .disabled(center.hasPausableDownloads == false)

            Button("Resume All") {
                center.resumeAll()
            }
            .disabled(center.hasResumableDownloads == false)

            Divider()

            Button("Reveal in Finder") {
                center.revealSelectedInFinder()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(center.selectedDownload == nil)

            Button("Open Downloaded File") {
                center.openSelectedDownload()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(center.canOpenSelectedDownload == false)

            Divider()

            Button("Remove Selected from List") {
                center.removeSelectedDownload()
            }
            .disabled(center.selectedDownload == nil)

            Button("Clear Completed") {
                center.clearCompleted()
            }
            .disabled(center.hasCompletedDownloads == false)

            Button("Clear Failed") {
                center.clearFailed()
            }
            .disabled(center.hasFailedDownloads == false)
        }
    }
}
