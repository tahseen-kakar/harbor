import SwiftUI

struct DownloadStatusBadge: View {
    let status: DownloadStatus

    private var tint: Color {
        switch status {
        case .queued:
            .secondary
        case .preparing:
            .orange
        case .downloading:
            .blue
        case .browserSessionRequired:
            .mint
        case .paused:
            .yellow
        case .completed:
            .green
        case .failed:
            .red
        case .cancelled:
            .secondary
        }
    }

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule(style: .continuous))
    }
}
