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
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Downloads")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                throughputMetric(
                    systemImage: "arrow.down.circle",
                    value: DownloadFormatting.throughputString(center.totalDownloadSpeed)
                )

                Divider()
                    .frame(height: 14)

                throughputMetric(
                    systemImage: "arrow.up.circle",
                    value: DownloadFormatting.throughputString(center.totalUploadSpeed)
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }

    private func throughputMetric(systemImage: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(value)
                .monospacedDigit()
        }
    }
}
