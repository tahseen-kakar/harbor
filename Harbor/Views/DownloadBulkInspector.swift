import SwiftUI

struct DownloadBulkInspector: View {
    let center: DownloadCenter
    @State private var pendingDataRemovalIDs: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(center.selectedDownloadIDs.count) Downloads Selected")
                    .font(.title2.weight(.semibold))

                if #available(macOS 26, *) {
                    GlassEffectContainer(spacing: 10) { actions }
                } else {
                    actions
                }
            }
            .padding(24)
        }
        .modifier(DownloadDataRemovalConfirmation(center: center, ids: $pendingDataRemovalIDs))
    }

    private var actions: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            DownloadSelectionActions(center: center, ids: center.selectedDownloadIDs, usesGrid: true) {
                pendingDataRemovalIDs = $0
            }
        }
    }
}
