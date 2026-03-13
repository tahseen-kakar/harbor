import SwiftUI

@main
struct HarborApp: App {
    @State private var settings: AppSettingsStore
    @State private var center: DownloadCenter
    @StateObject private var updater: AppUpdater

    init() {
        let settings = AppSettingsStore()
        _settings = State(initialValue: settings)
        _center = State(initialValue: DownloadCenter(settings: settings))
        _updater = StateObject(wrappedValue: AppUpdater())
    }

    var body: some Scene {
        WindowGroup {
            RootView(center: center, settings: settings)
                .frame(minWidth: 1_040, minHeight: 680)
                .task {
                    await center.initializeIfNeeded()
                }
        }
        .defaultSize(width: 1_320, height: 820)
        .defaultPosition(.center)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .commands {
            DownloadCommands(center: center, updater: updater)
        }

        Settings {
            SettingsView(settings: settings, updater: updater)
                .frame(width: 480, height: 340)
                .padding(20)
        }
        .windowResizability(.contentSize)
    }
}
