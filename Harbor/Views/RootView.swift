import SwiftUI

struct RootView: View {
    let center: DownloadCenter
    let settings: AppSettingsStore

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
        } content: {
            DownloadsContentView(center: center)
                .navigationSplitViewColumnWidth(
                    min: Layout.contentMinWidth,
                    ideal: Layout.contentIdealWidth
                )
        } detail: {
            DownloadDetailView(center: center)
                .navigationSplitViewColumnWidth(
                    min: Layout.inspectorMinWidth,
                    ideal: Layout.inspectorIdealWidth,
                    max: Layout.inspectorMaxWidth
                )
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $center.searchText, placement: .toolbar, prompt: "Search downloads")
        .sheet(item: $center.addSheetDraft, onDismiss: {
            center.handleAddSheetDismissal()
        }) { draft in
            AddDownloadSheet(settings: settings, draft: draft) { request in
                center.queueDownload(request)
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
            Button("OK", role: .cancel) {
                center.activeAlert = nil
            }
        } message: {
            Text(center.activeAlert?.message ?? "")
        }
        .toolbar {
            DownloadToolbarContent(center: center)
        }
    }
}

private struct DownloadToolbarContent: ToolbarContent {
    @Bindable var center: DownloadCenter

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("New Download", systemImage: "plus") {
                center.presentAddSheet()
            }

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
            .disabled(
                center.hasActiveDownloads
                    ? center.hasPausableDownloads == false
                    : center.hasResumableDownloads == false
            )

            Button("Reveal", systemImage: "folder") {
                center.revealSelectedInFinder()
            }
            .disabled(center.selectedDownload == nil)
        }

        ToolbarItem {
            Menu {
                Picker("Sort", selection: $center.sortMode) {
                    ForEach(DownloadSortMode.allCases) { sortMode in
                        Text(sortMode.title).tag(sortMode)
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down.circle")
            }
            .disabled(center.downloads.isEmpty)
        }
    }
}

#Preview("Harbor Window") {
    let settings = HarborPreviewFixtures.makeSettings()
    let center = HarborPreviewFixtures.makeCenter()

    RootView(center: center, settings: settings)
        .frame(width: 1_320, height: 820)
}
