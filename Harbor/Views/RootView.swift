import SwiftUI

struct RootView: View {
    let center: DownloadCenter
    let settings: AppSettingsStore

    var body: some View {
        @Bindable var center = center

        NavigationSplitView {
            SidebarView(center: center)
                .frame(minWidth: 220, idealWidth: 240)
        } content: {
            DownloadsContentView(center: center)
                .frame(minWidth: 560)
        } detail: {
            DownloadDetailView(center: center)
                .frame(minWidth: 320, idealWidth: 360)
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $center.searchText, placement: .toolbar, prompt: "Search downloads")
        .sheet(isPresented: $center.isPresentingAddSheet) {
            AddDownloadSheet(settings: settings) { request in
                center.queueDownload(request)
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

                if center.selectedDownload != nil {
                    Button("Reveal", systemImage: "folder") {
                        center.revealSelectedInFinder()
                    }
                }
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
            }
        }
    }
}

#Preview("Harbor Window") {
    let settings = HarborPreviewFixtures.makeSettings()
    let center = HarborPreviewFixtures.makeCenter()

    RootView(center: center, settings: settings)
        .frame(width: 1_320, height: 820)
}
