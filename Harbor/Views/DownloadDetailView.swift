import SwiftUI

struct DownloadDetailView: View {
    let center: DownloadCenter

    private let metricColumns = [
        GridItem(.flexible(minimum: 120), spacing: 12),
        GridItem(.flexible(minimum: 120), spacing: 12)
    ]

    var body: some View {
        Group {
            if let item = center.selectedDownload {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        overviewCard(for: item)
                        storageCard(for: item)

                        if let message = item.lastError, item.status == .failed {
                            errorCard(message: message)
                        }
                    }
                    .padding(24)
                }
                .background(detailPaneBackground)
                .navigationTitle(item.displayName)
            } else {
                ContentUnavailableView {
                    Label("Select a Download", systemImage: "sidebar.right")
                } description: {
                    Text("Choose any row to inspect progress, speed, file location, and recovery actions.")
                } actions: {
                    primaryActionButton(
                        title: "Add Download",
                        systemImage: "plus",
                        isProminent: true
                    ) {
                        center.presentAddSheet()
                    }
                }
                .background(detailPaneBackground)
            }
        }
    }

    private func overviewCard(for item: DownloadItem) -> some View {
        inspectorCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.quaternary.opacity(0.55))

                    Image(systemName: item.sourceBadgeImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.displayName)
                        .font(.title2.weight(.semibold))
                        .lineLimit(3)

                    HStack(spacing: 8) {
                        Label(item.sourceBadgeTitle, systemImage: item.sourceBadgeImage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        if let summary = sourceSummary(for: item) {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let sourceLine = sourceLine(for: item) {
                        Text(sourceLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 16)

                DownloadStatusBadge(status: item.status)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Progress")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(progressLabel(for: item))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if let progressValue = item.progressValue {
                    ProgressView(value: progressValue, total: 1)
                        .tint(progressTint(for: item))
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            LazyVGrid(columns: metricColumns, spacing: 12) {
                metricTile(
                    title: "Downloaded",
                    value: item.progressText,
                    systemImage: "arrow.down.circle"
                )

                metricTile(
                    title: "Download Speed",
                    value: item.speedText,
                    systemImage: "speedometer"
                )

                if item.backend == .aria2 {
                    metricTile(
                        title: "Upload Speed",
                        value: DownloadFormatting.throughputString(item.uploadBytesPerSecond),
                        systemImage: "arrow.up.circle"
                    )
                }

                if let eta = item.etaText {
                    metricTile(
                        title: "ETA",
                        value: eta,
                        systemImage: "clock"
                    )
                }
            }

            actionBar(for: item)

            activityFootnote(for: item)
        }
    }

    private func storageCard(for item: DownloadItem) -> some View {
        inspectorCard {
            Text("Storage")
                .font(.headline)

            pathRow(
                title: "Destination",
                systemImage: "folder",
                path: item.destinationFolderPath
            )

            if let fileLocationPath = item.fileLocationPath {
                pathRow(
                    title: "Saved File",
                    systemImage: "doc",
                    path: fileLocationPath
                )
            }
        }
    }

    private func errorCard(message: String) -> some View {
        inspectorCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Error")
                        .font(.headline)
                    Text(message)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func actionBar(for item: DownloadItem) -> some View {
        ViewThatFits {
            HStack(spacing: 10) {
                primaryTransportAction(for: item)
                auxiliaryAction(for: item)
                overflowMenu(for: item)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                primaryTransportAction(for: item)
                HStack(spacing: 10) {
                    auxiliaryAction(for: item)
                    overflowMenu(for: item)
                }
            }
        }
    }

    @ViewBuilder
    private func primaryTransportAction(for item: DownloadItem) -> some View {
        let isPause = item.canPause

        primaryActionButton(
            title: isPause ? "Pause" : "Resume",
            systemImage: isPause ? "pause.fill" : "play.fill",
            isProminent: true
        ) {
            center.togglePauseResume(id: item.id)
        }
    }

    @ViewBuilder
    private func auxiliaryAction(for item: DownloadItem) -> some View {
        if item.status == .failed || item.status == .cancelled {
            secondaryActionButton(
                title: "Retry",
                systemImage: "arrow.clockwise"
            ) {
                center.retryDownload(id: item.id)
            }
        } else if item.fileLocationURL != nil {
            secondaryActionButton(
                title: "Open File",
                systemImage: "doc.fill"
            ) {
                center.openDownload(id: item.id)
            }
        }
    }

    private func overflowMenu(for item: DownloadItem) -> some View {
        Menu {
            Button("Reveal in Finder", systemImage: "folder") {
                center.revealInFinder(id: item.id)
            }

            if item.fileLocationURL != nil,
               item.status == .failed || item.status == .cancelled {
                Button("Open File", systemImage: "doc") {
                    center.openDownload(id: item.id)
                }
            }

            Button("Copy Source URL", systemImage: "link") {
                center.copySourceURL(id: item.id)
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .frame(minWidth: 72)
        }
        .modifier(GlassButtonModifier(prominent: false))
    }

    private func activityFootnote(for item: DownloadItem) -> some View {
        HStack(spacing: 10) {
            Label(
                "Added \(DownloadFormatting.dateString(item.createdAt))",
                systemImage: "calendar"
            )

            if let finishedAt = item.finishedAt {
                Text("•")
                Label(
                    "Finished \(DownloadFormatting.dateString(finishedAt))",
                    systemImage: "checkmark.circle"
                )
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func pathRow(title: String, systemImage: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Text(path)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.quaternary.opacity(0.36), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metricTile(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.36), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func progressLabel(for item: DownloadItem) -> String {
        if let progressValue = item.progressValue {
            return "\(Int((progressValue * 100).rounded()))%"
        }

        return item.status == .preparing ? "Starting…" : item.status.title
    }

    private func progressTint(for item: DownloadItem) -> Color {
        switch item.status {
        case .downloading:
            .blue
        case .paused:
            .yellow
        case .completed:
            .green
        case .failed:
            .red
        case .cancelled:
            .secondary
        case .queued, .preparing:
            .orange
        }
    }

    private func sourceSummary(for item: DownloadItem) -> String? {
        switch item.sourceKind {
        case .directURL:
            item.sourceURL.host
        case .magnetLink:
            "BitTorrent"
        case .torrentFile:
            nil
        }
    }

    private func sourceLine(for item: DownloadItem) -> String? {
        switch item.sourceKind {
        case .directURL:
            item.sourceURL.absoluteString
        case .magnetLink:
            nil
        case .torrentFile:
            item.sourceURL.lastPathComponent
        }
    }

    @ViewBuilder
    private func inspectorCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        let body = VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(18)

        if #available(macOS 26, *) {
            body
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else {
            body
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.35))
                }
        }
    }

    private var detailPaneBackground: some View {
        Rectangle()
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: 2)
            }
            .ignoresSafeArea()
    }

    private func primaryActionButton(
        title: String,
        systemImage: String,
        isProminent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(minWidth: 96)
        }
        .modifier(GlassButtonModifier(prominent: isProminent))
    }

    private func secondaryActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .modifier(GlassButtonModifier(prominent: false))
    }
}

private struct GlassButtonModifier: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                content
                    .buttonStyle(.glassProminent)
                    .controlSize(.regular)
            } else {
                content
                    .buttonStyle(.glass)
                    .controlSize(.regular)
            }
        } else {
            if prominent {
                content
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            } else {
                content
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
        }
    }
}
