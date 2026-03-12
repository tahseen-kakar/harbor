import SwiftUI

struct SettingsView: View {
    let settings: AppSettingsStore
    @Environment(\.openURL) private var openURL

    @State private var isCheckingForUpdates = false
    @State private var updateStatusMessage: String?
    @State private var availableRelease: AppUpdateChecker.Release?
    @State private var activeAlert: UserAlert?

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
                    Text(currentVersionLabel)
                        .foregroundStyle(.secondary)
                }

                if let availableRelease {
                    LabeledContent("Latest Release") {
                        Text(availableRelease.version)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button("Check for Updates…") {
                        Task {
                            await checkForUpdates()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCheckingForUpdates)

                    if isCheckingForUpdates {
                        ProgressView()
                            .controlSize(.small)
                    } else if let availableRelease {
                        Button("Download Update") {
                            openURL(availableRelease.preferredDownloadURL)
                        }
                    }
                }

                Text(updateStatusMessage ?? "Check Harbor's GitHub Releases for a newer build.")
                    .foregroundStyle(.secondary)

                Text("When an update is available, Harbor opens the latest DMG, package, ZIP asset, or the public release page so users can install the newest build.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Update Available",
            isPresented: isShowingUpdateDialog,
            titleVisibility: .visible,
            presenting: availableRelease
        ) { release in
            Button("Download Update") {
                openURL(release.preferredDownloadURL)
            }

            Button("View Release Notes") {
                openURL(release.htmlURL)
            }

            Button("Not Now", role: .cancel) {}
        } message: { release in
            Text("\(release.displayName) is available. You're running Harbor \(currentVersionLabel).")
        }
        .alert(item: $activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var currentVersionLabel: String {
        let shortVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "Unknown"
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""

        if build.isEmpty || build == shortVersion {
            return shortVersion
        }

        return "\(shortVersion) (\(build))"
    }

    private var isShowingUpdateDialog: Binding<Bool> {
        Binding(
            get: { availableRelease != nil },
            set: { isPresented in
                if isPresented == false {
                    availableRelease = nil
                }
            }
        )
    }

    @MainActor
    private func checkForUpdates() async {
        isCheckingForUpdates = true
        availableRelease = nil
        updateStatusMessage = nil
        defer { isCheckingForUpdates = false }

        do {
            switch try await AppUpdateChecker.checkForUpdates() {
            case let .upToDate(currentVersion):
                updateStatusMessage = "Harbor \(currentVersion) is already up to date."

            case let .updateAvailable(currentVersion, release):
                updateStatusMessage = "\(release.displayName) is available. You're running Harbor \(currentVersion)."
                availableRelease = release
            }
        } catch {
            activeAlert = UserAlert(
                title: "Unable to Check for Updates",
                message: error.localizedDescription
            )
        }
    }
}

#Preview("Settings") {
    SettingsView(settings: HarborPreviewFixtures.makeSettings())
        .frame(width: 520, height: 520)
        .padding(20)
}
