import SwiftUI

struct SettingsView: View {
    let settings: AppSettingsStore

    var body: some View {
        @Bindable var settings = settings
        let aria2Resolution = Aria2BinaryResolver.resolveBinary()

        Form {
            Section("General") {
                LabeledContent("Default Destination") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(settings.defaultDestinationPath)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)

                        HStack(spacing: 8) {
                            Button("Choose…") {
                                settings.chooseDefaultDestination()
                            }

                            Button("Reveal") {
                                settings.revealDefaultDestination()
                            }
                        }
                    }
                }

                Stepper(value: $settings.maxConcurrentDownloads, in: 1 ... 8) {
                    LabeledContent("Concurrent Downloads", value: "\(settings.maxConcurrentDownloads)")
                }

                Toggle("Start downloads immediately", isOn: $settings.startDownloadsAutomatically)
            }

            Section("Behavior") {
                Text("Active downloads use native `URLSessionDownloadTask` transfers with pause and resume support when the server exposes resume data.")
                    .foregroundStyle(.secondary)
                Text("Magnet links and `.torrent` files are routed through `aria2c` over local JSON-RPC so the app can stay native while delegating BitTorrent protocol work to a dedicated engine.")
                    .foregroundStyle(.secondary)
                Text("Completed files are stored directly on disk and the queue history is persisted in Application Support.")
                    .foregroundStyle(.secondary)
            }

            Section("Torrent Engine") {
                LabeledContent("Status") {
                    Text(aria2Resolution?.source.displayName ?? "Unavailable")
                        .foregroundStyle(aria2Resolution == nil ? Color.red : Color.secondary)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("aria2c") {
                    Text(aria2Resolution?.url.path ?? "Not found")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                Text("Release builds should include Harbor’s bundled aria2 runtime so users can install the app and use torrents immediately. `ARIA2C_PATH` remains available as a development override.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview("Settings") {
    SettingsView(settings: HarborPreviewFixtures.makeSettings())
        .frame(width: 520, height: 420)
        .padding(20)
}
