import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppSettingsStore {
    private enum Keys {
        static let defaultDestinationPath = "defaultDestinationPath"
        static let maxConcurrentDownloads = "maxConcurrentDownloads"
        static let startDownloadsAutomatically = "startDownloadsAutomatically"
        static let notificationsEnabled = "notificationsEnabled"
    }

    private let userDefaults: UserDefaults

    var defaultDestinationPath: String {
        didSet {
            userDefaults.set(defaultDestinationPath, forKey: Keys.defaultDestinationPath)
        }
    }

    var maxConcurrentDownloads: Int {
        didSet {
            userDefaults.set(maxConcurrentDownloads, forKey: Keys.maxConcurrentDownloads)
        }
    }

    var startDownloadsAutomatically: Bool {
        didSet {
            userDefaults.set(startDownloadsAutomatically, forKey: Keys.startDownloadsAutomatically)
        }
    }

    var notificationsEnabled: Bool {
        didSet {
            userDefaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let defaultDownloadsPath = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first?.path ?? NSHomeDirectory()

        self.defaultDestinationPath = userDefaults.string(forKey: Keys.defaultDestinationPath) ?? defaultDownloadsPath

        let storedConcurrency = userDefaults.integer(forKey: Keys.maxConcurrentDownloads)
        self.maxConcurrentDownloads = storedConcurrency == 0 ? 3 : storedConcurrency

        if userDefaults.object(forKey: Keys.startDownloadsAutomatically) == nil {
            self.startDownloadsAutomatically = true
        } else {
            self.startDownloadsAutomatically = userDefaults.bool(forKey: Keys.startDownloadsAutomatically)
        }

        if userDefaults.object(forKey: Keys.notificationsEnabled) == nil {
            self.notificationsEnabled = true
        } else {
            self.notificationsEnabled = userDefaults.bool(forKey: Keys.notificationsEnabled)
        }
    }

    var defaultDestinationURL: URL {
        URL(fileURLWithPath: defaultDestinationPath, isDirectory: true)
    }

    func chooseDefaultDestination() {
        guard let folder = FolderSelectionService.chooseFolder(startingAt: defaultDestinationURL) else {
            return
        }

        defaultDestinationPath = folder.path
    }

    func revealDefaultDestination() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: defaultDestinationPath)
    }
}
