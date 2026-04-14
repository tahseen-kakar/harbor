import AppKit
import Foundation
import Observation

struct DownloadTransferSettings: Equatable, Sendable {
    nonisolated static var `default`: DownloadTransferSettings {
        DownloadTransferSettings(
            maxConcurrentDownloads: 3,
            globalSpeedLimitBytesPerSecond: nil,
            perDownloadSpeedLimitBytesPerSecond: nil,
            perDownloadConnectionCount: 4
        )
    }

    let maxConcurrentDownloads: Int
    let globalSpeedLimitBytesPerSecond: Int64?
    let perDownloadSpeedLimitBytesPerSecond: Int64?
    let perDownloadConnectionCount: Int
}

@Observable
@MainActor
final class AppSettingsStore {
    private enum Keys {
        static let defaultDestinationPath = "defaultDestinationPath"
        static let maxConcurrentDownloads = "maxConcurrentDownloads"
        static let startDownloadsAutomatically = "startDownloadsAutomatically"
        static let notificationsEnabled = "notificationsEnabled"
        static let globalSpeedLimitEnabled = "globalSpeedLimitEnabled"
        static let globalSpeedLimitKilobytesPerSecond = "globalSpeedLimitKilobytesPerSecond"
        static let perDownloadSpeedLimitEnabled = "perDownloadSpeedLimitEnabled"
        static let perDownloadSpeedLimitKilobytesPerSecond = "perDownloadSpeedLimitKilobytesPerSecond"
        static let perDownloadConnectionCount = "perDownloadConnectionCount"
    }

    static let maxConcurrentDownloadsRange = 1 ... 16
    static let perDownloadConnectionCountRange = 1 ... 16
    static let speedLimitKilobytesRange = 1 ... 1_048_576

    private let userDefaults: UserDefaults
    @ObservationIgnored var transferSettingsDidChange: ((DownloadTransferSettings) -> Void)?

    var defaultDestinationPath: String {
        didSet {
            userDefaults.set(defaultDestinationPath, forKey: Keys.defaultDestinationPath)
        }
    }

    var maxConcurrentDownloads: Int {
        didSet {
            userDefaults.set(maxConcurrentDownloads, forKey: Keys.maxConcurrentDownloads)
            notifyTransferSettingsChanged()
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

    var globalSpeedLimitEnabled: Bool {
        didSet {
            userDefaults.set(globalSpeedLimitEnabled, forKey: Keys.globalSpeedLimitEnabled)
            notifyTransferSettingsChanged()
        }
    }

    var globalSpeedLimitKilobytesPerSecond: Int {
        didSet {
            userDefaults.set(globalSpeedLimitKilobytesPerSecond, forKey: Keys.globalSpeedLimitKilobytesPerSecond)
            notifyTransferSettingsChanged()
        }
    }

    var perDownloadSpeedLimitEnabled: Bool {
        didSet {
            userDefaults.set(perDownloadSpeedLimitEnabled, forKey: Keys.perDownloadSpeedLimitEnabled)
            notifyTransferSettingsChanged()
        }
    }

    var perDownloadSpeedLimitKilobytesPerSecond: Int {
        didSet {
            userDefaults.set(perDownloadSpeedLimitKilobytesPerSecond, forKey: Keys.perDownloadSpeedLimitKilobytesPerSecond)
            notifyTransferSettingsChanged()
        }
    }

    var perDownloadConnectionCount: Int {
        didSet {
            userDefaults.set(perDownloadConnectionCount, forKey: Keys.perDownloadConnectionCount)
            notifyTransferSettingsChanged()
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
        self.maxConcurrentDownloads = Self.clamped(
            storedConcurrency == 0 ? 3 : storedConcurrency,
            to: Self.maxConcurrentDownloadsRange
        )

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

        self.globalSpeedLimitEnabled = userDefaults.bool(forKey: Keys.globalSpeedLimitEnabled)
        self.globalSpeedLimitKilobytesPerSecond = Self.clamped(
            userDefaults.integer(forKey: Keys.globalSpeedLimitKilobytesPerSecond) == 0
                ? 25 * 1_024
                : userDefaults.integer(forKey: Keys.globalSpeedLimitKilobytesPerSecond),
            to: Self.speedLimitKilobytesRange
        )

        self.perDownloadSpeedLimitEnabled = userDefaults.bool(forKey: Keys.perDownloadSpeedLimitEnabled)
        self.perDownloadSpeedLimitKilobytesPerSecond = Self.clamped(
            userDefaults.integer(forKey: Keys.perDownloadSpeedLimitKilobytesPerSecond) == 0
                ? 5 * 1_024
                : userDefaults.integer(forKey: Keys.perDownloadSpeedLimitKilobytesPerSecond),
            to: Self.speedLimitKilobytesRange
        )

        let storedConnectionCount = userDefaults.integer(forKey: Keys.perDownloadConnectionCount)
        self.perDownloadConnectionCount = Self.clamped(
            storedConnectionCount == 0 ? 4 : storedConnectionCount,
            to: Self.perDownloadConnectionCountRange
        )
    }

    var defaultDestinationURL: URL {
        URL(fileURLWithPath: defaultDestinationPath, isDirectory: true)
    }

    var transferSettings: DownloadTransferSettings {
        DownloadTransferSettings(
            maxConcurrentDownloads: Self.clamped(maxConcurrentDownloads, to: Self.maxConcurrentDownloadsRange),
            globalSpeedLimitBytesPerSecond: speedLimitBytesPerSecond(
                isEnabled: globalSpeedLimitEnabled,
                kilobytesPerSecond: globalSpeedLimitKilobytesPerSecond
            ),
            perDownloadSpeedLimitBytesPerSecond: speedLimitBytesPerSecond(
                isEnabled: perDownloadSpeedLimitEnabled,
                kilobytesPerSecond: perDownloadSpeedLimitKilobytesPerSecond
            ),
            perDownloadConnectionCount: Self.clamped(
                perDownloadConnectionCount,
                to: Self.perDownloadConnectionCountRange
            )
        )
    }

    static func clampedSpeedLimitKilobytes(_ value: Int) -> Int {
        clamped(value, to: speedLimitKilobytesRange)
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

    private func notifyTransferSettingsChanged() {
        transferSettingsDidChange?(transferSettings)
    }

    private func speedLimitBytesPerSecond(
        isEnabled: Bool,
        kilobytesPerSecond: Int
    ) -> Int64? {
        guard isEnabled else {
            return nil
        }

        return Int64(Self.clampedSpeedLimitKilobytes(kilobytesPerSecond)) * 1_024
    }

    private static func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
