import Foundation

enum TransferLimitOverride: Codable, Equatable, Hashable, Sendable {
    case inherit
    case unlimited
    case limited(kilobytesPerSecond: Int)

    init(bytesPerSecond: Int64?) {
        self = bytesPerSecond.map { .limited(kilobytesPerSecond: Int($0 / 1_024)) } ?? .unlimited
    }

    nonisolated func resolvedBytesPerSecond(inheriting defaultLimit: Int64?) -> Int64? {
        switch self {
        case .inherit:
            return defaultLimit
        case .unlimited:
            return nil
        case let .limited(kilobytesPerSecond):
            let clampedKilobytes = Int64(clamping: max(kilobytesPerSecond, 1))
            let (bytesPerSecond, didOverflow) = clampedKilobytes.multipliedReportingOverflow(by: 1_024)
            return didOverflow ? Int64.max : bytesPerSecond
        }
    }
}

extension DownloadItem {
    var trafficModeOverride: TrafficMode? {
        guard downloadLimitOverride != .inherit
            || (backend == .aria2 && uploadLimitOverride != .inherit) else { return nil }
        return [TrafficMode.unlimited, .balanced, .quiet].first { mode in
            let limits = mode.applying(to: .default)
            return downloadLimitOverride == TransferLimitOverride(bytesPerSecond: limits.perDownloadSpeedLimitBytesPerSecond)
                && (backend != .aria2
                    || uploadLimitOverride == TransferLimitOverride(bytesPerSecond: limits.perDownloadUploadSpeedLimitBytesPerSecond))
        } ?? .custom
    }
}
