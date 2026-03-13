import SwiftUI

struct SettingsView: View {
    let settings: AppSettingsStore
    @ObservedObject var updater: AppUpdater

    var body: some View {
        @Bindable var settings = settings

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

            Section("Updates") {
                LabeledContent("Current Version") {
                    Text(updater.currentVersionLabel)
                        .foregroundStyle(.secondary)
                }

                Toggle(
                    "Automatically check for updates",
                    isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.setAutomaticallyChecksForUpdates($0) }
                    )
                )

                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .buttonStyle(.borderedProminent)
                .disabled(updater.canCheckForUpdates == false)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview("Settings") {
    SettingsView(
        settings: HarborPreviewFixtures.makeSettings(),
        updater: AppUpdater.preview()
    )
        .frame(width: 520, height: 520)
        .padding(20)
}
