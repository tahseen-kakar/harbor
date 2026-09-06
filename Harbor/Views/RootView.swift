import Foundation
import SwiftUI

struct RootView: View {
    let center: DownloadCenter
    let settings: AppSettingsStore
    @AppStorage("downloads.inspector.width")
    private var storedInspectorWidth = Double(Layout.inspectorIdealWidth)
    @State private var isDownloadDropTargeted = false
    @FocusState private var isSearchFocused: Bool

    private enum Layout {
        static let sidebarMinWidth: CGFloat = 200
        static let sidebarIdealWidth: CGFloat = 230
        static let sidebarMaxWidth: CGFloat = 280
        static let contentMinWidth: CGFloat = 500
        static let contentIdealWidth: CGFloat = 680
        static let inspectorMinWidth: CGFloat = 300
        static let inspectorIdealWidth: CGFloat = 340
        static let inspectorMaxWidth: CGFloat = 440
    }

    var body: some View {
        @Bindable var center = center

        NavigationSplitView {
            SidebarView(center: center)
                .navigationSplitViewColumnWidth(
                    min: Layout.sidebarMinWidth,
                    ideal: Layout.sidebarIdealWidth,
                    max: Layout.sidebarMaxWidth
                )
        } detail: {
            DownloadsContentView(center: center)
                .navigationSplitViewColumnWidth(
                    min: Layout.contentMinWidth,
                    ideal: Layout.contentIdealWidth
                )
                .inspector(isPresented: inspectorPresentation) {
                    DownloadDetailView(center: center)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.width
                        } action: { width in
                            persistInspectorWidth(width)
                        }
                        .inspectorColumnWidth(
                            min: Layout.inspectorMinWidth,
                            ideal: restoredInspectorWidth,
                            max: Layout.inspectorMaxWidth
                        )
                }
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityIdentifier(HarborAccessibility.root)
        .searchable(text: $center.searchText, placement: .toolbar, prompt: "Search downloads")
        .searchFocused($isSearchFocused)
        .focusedSceneValue(\.focusDownloadSearch, focusSearch)
        .sheet(item: $center.addSheetDraft, onDismiss: {
            center.handleAddSheetDismissal()
        }) { draft in
            AddDownloadSheet(
                settings: settings,
                draft: draft,
                mediaPreviewProvider: { url in
                    try await center.previewMediaDownload(for: url)
                },
                torrentPreviewProvider: { sourceKind, url, requestHeaders in
                    try await center.previewTorrentContents(
                        sourceKind: sourceKind,
                        sourceURL: url,
                        requestHeaders: requestHeaders
                    )
                }
            ) { requests in
                center.queueDownloads(requests)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { center.activeBrowserSession != nil },
                set: { isPresented in
                    if isPresented == false {
                        center.dismissBrowserSession()
                    }
                }
            )
        ) {
            if let session = center.activeBrowserSession {
                BrowserDownloadSheet(center: center, session: session)
            }
        }
        .alert(
            center.activeAlert?.title ?? "Alert",
            isPresented: Binding(
                get: { center.activeAlert != nil },
                set: { isPresented in
                    if isPresented == false {
                        center.activeAlert = nil
                    }
                }
            )
        ) {
            if center.canRetryInitialization {
                Button("Retry") {
                    center.activeAlert = nil
                    Task {
                        await center.initializeIfNeeded()
                    }
                }
            } else {
                Button("OK", role: .cancel) {
                    center.activeAlert = nil
                }
            }
        } message: {
            Text(center.activeAlert?.message ?? "")
        }
        // TODO: Revisit customizable toolbars after macOS 26 stops crashing while restoring toolbar items during file opens.
        .toolbar {
            DownloadToolbarContent(center: center, settings: settings)
        }
        .onDrop(
            of: DownloadSourceImportService.supportedContentTypes,
            isTargeted: $isDownloadDropTargeted,
            perform: loadExternalAddSources
        )
        .onPasteCommand(of: DownloadSourceImportService.supportedContentTypes) { providers in
            _ = loadExternalAddSources(providers)
        }
        .overlay {
            if isDownloadDropTargeted {
                DownloadDropTargetOverlay()
                    .allowsHitTesting(false)
            }
        }
    }

    private var inspectorPresentation: Binding<Bool> {
        Binding(
            get: { center.selectedDownload != nil },
            set: { isPresented in
                if isPresented == false {
                    center.selectedDownloadIDs = []
                }
            }
        )
    }

    private var restoredInspectorWidth: CGFloat {
        min(
            max(CGFloat(storedInspectorWidth), Layout.inspectorMinWidth),
            Layout.inspectorMaxWidth
        )
    }

    private func persistInspectorWidth(_ width: CGFloat) {
        guard width.isFinite,
              width >= Layout.inspectorMinWidth - 1,
              width <= Layout.inspectorMaxWidth + 1 else {
            return
        }

        let clampedWidth = min(
            max(width, Layout.inspectorMinWidth),
            Layout.inspectorMaxWidth
        )
        guard abs(storedInspectorWidth - Double(clampedWidth)) >= 0.5 else {
            return
        }

        storedInspectorWidth = Double(clampedWidth)
    }

    private func loadExternalAddSources(_ providers: [NSItemProvider]) -> Bool {
        DownloadSourceImportService.loadSupportedURLs(from: providers) { urls in
            center.receiveExternalAddSources(urls)
        }
    }

    private func focusSearch() {
        isSearchFocused = true
    }
}

private struct DownloadDropTargetOverlay: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.04))

            Label("Drop to Add Download", systemImage: "arrow.down.doc")
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.quaternary)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(14)
        }
    }
}

private struct DownloadToolbarContent: ToolbarContent {
    @Bindable var center: DownloadCenter
    @Bindable var settings: AppSettingsStore

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("New Download", systemImage: "plus") {
                center.presentAddSheet()
            }
            .accessibilityIdentifier(HarborAccessibility.newDownload)
            .disabled(center.canAddDownloads == false)
        }

        ToolbarItem(placement: .primaryAction) {
            Button(
                center.hasActiveDownloads ? "Pause All" : "Resume All",
                systemImage: center.hasActiveDownloads ? "pause.fill" : "play.fill"
            ) {
                if center.hasActiveDownloads {
                    center.pauseAll()
                } else {
                    center.resumeAll()
                }
            }
            .accessibilityIdentifier(HarborAccessibility.pauseResumeAll)
            .disabled(
                center.hasActiveDownloads
                    ? center.hasPausableDownloads == false
                    : center.hasResumableDownloads == false
            )
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(TrafficMode.allCases) { mode in
                    Toggle(
                        mode.title,
                        isOn: Binding(
                            get: { settings.trafficMode == mode },
                            set: { isSelected in
                                if isSelected {
                                    settings.trafficMode = mode
                                }
                            }
                        )
                    )
                }

                Divider()

                SettingsLink {
                    Label("Edit Limits…", systemImage: "gearshape")
                }
            } label: {
                Label(settings.trafficMode.title, systemImage: "speedometer")
                    .labelStyle(.titleAndIcon)
            }
            .help("Traffic Mode")
        }

        ToolbarItem(placement: .primaryAction) {
            Button("Reveal", systemImage: "folder") {
                center.revealSelectedInFinder()
            }
            .disabled(center.selectedDownload == nil)
        }
    }
}

#Preview("Harbor Window") {
    let settings = HarborPreviewFixtures.makeSettings()
    let center = HarborPreviewFixtures.makeCenter()

    RootView(center: center, settings: settings)
        .frame(width: 1_320, height: 820)
}
