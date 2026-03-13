import SwiftUI

struct CheckForUpdatesCommandView: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(updater.canCheckForUpdates == false)
    }
}
