import SwiftUI
import AppKit
import AIUsageCore

struct PopoverView: View {
    @Bindable var store: UsageStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label {
                    Text("AI Usage")
                } icon: {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable().frame(width: 24, height: 24)
                }.font(.headline)
                Spacer()
                Button {
                    let location = Bundle.main.bundleURL.path
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .credits: NSAttributedString(string: "Claude Code + Codex usage\n\nRunning from:\n\(location)")
                    ])
                    NSApplication.shared.activate()
                } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.plain)
                    .help("About AIUsage: version and running copy")
                    .accessibilityLabel("About AIUsage")
                Button { store.refreshNow() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
                    .disabled(store.isRefreshing)
                    .help("Refresh usage (at least one minute between requests; server retry times are respected)")
                    .accessibilityLabel("Refresh usage")
            }
            ForEach(Provider.allCases) { provider in ProviderCardView(state: store.state(for: provider)) }
            Divider()
            UsageChartView(store: store)
            if let message = store.cacheMessage { Text(message).font(.caption2).foregroundStyle(.secondary) }
            Divider()
            FooterView(store: store)
        }
        .padding(16)
        .frame(width: 360)
        .onAppear { store.popoverOpened() }
    }
}
