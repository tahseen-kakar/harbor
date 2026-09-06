import SwiftUI

struct SidebarView: View {
    let center: DownloadCenter

    var body: some View {
        @Bindable var center = center

        List(selection: $center.selectedFilter) {
            Section("Library") {
                ForEach(DownloadFilter.allCases) { filter in
                    HStack(spacing: 10) {
                        Label(filter.title, systemImage: filter.systemImage)
                        Spacer()
                        Text(center.count(for: filter), format: .number)
                            .foregroundStyle(.secondary)
                    }
                    .tag(filter)
                    .accessibilityIdentifier(HarborAccessibility.sidebarFilter(filter))
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier(HarborAccessibility.sidebar)
        .navigationTitle("Downloads")
    }
}

#Preview("Sidebar") {
    SidebarView(center: HarborPreviewFixtures.makeCenter())
        .frame(width: 260, height: 760)
}
