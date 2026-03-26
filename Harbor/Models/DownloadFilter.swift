import Foundation

enum DownloadFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case active
    case paused
    case completed
    case failed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All Downloads"
        case .active:
            "Active"
        case .paused:
            "Paused"
        case .completed:
            "Completed"
        case .failed:
            "Failed"
        case .cancelled:
            "Cancelled"
        }
    }

    var subtitle: String {
        switch self {
        case .all:
            "Everything in your queue and history"
        case .active:
            "Running and queued transfers"
        case .paused:
            "Ready to resume or continue in browser"
        case .completed:
            "Saved successfully"
        case .failed:
            "Needs attention"
        case .cancelled:
            "Stopped manually"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            "tray.full"
        case .active:
            "arrow.down.circle"
        case .paused:
            "pause.circle"
        case .completed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        case .cancelled:
            "xmark.circle"
        }
    }

    @MainActor
    func includes(_ item: DownloadItem) -> Bool {
        switch self {
        case .all:
            true
        case .active:
            item.status == .queued || item.status == .preparing || item.status == .downloading
        case .paused:
            item.status == .paused || item.status == .browserSessionRequired
        case .completed:
            item.status == .completed
        case .failed:
            item.status == .failed
        case .cancelled:
            item.status == .cancelled
        }
    }
}

enum DownloadSortMode: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case name
    case progress
    case speed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest:
            "Newest First"
        case .oldest:
            "Oldest First"
        case .name:
            "Name"
        case .progress:
            "Progress"
        case .speed:
            "Speed"
        }
    }
}
