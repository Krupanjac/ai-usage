import SwiftUI
import AIUsageCore

struct MenuBarLabel: View {
    var store: UsageStore
    var body: some View {
        Image(systemName: "chart.bar.fill")
        Text(store.menuBarText).monospacedDigit()
            .accessibilityLabel("AI Usage. Claude Code and Codex: \(store.menuBarText)")
            .help("AIUsage \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · Claude Code and Codex")
    }
}
