import SwiftUI
import AIUsageCore

struct QuotaBarView: View {
    var title: String
    var window: QuotaWindow?
    var tint: Color
    var missingText: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(title).font(.caption).frame(width: 42, alignment: .leading)
                if let window {
                    ProgressView(value: min(100, window.usedPercent), total: 100)
                        .tint(window.usedPercent >= 90 ? .red : tint)
                        .accessibilityLabel("\(title) quota used")
                        .accessibilityValue("\(Int(window.usedPercent.rounded())) percent")
                    Text("\(Int(window.usedPercent.rounded()))%")
                        .font(.system(.caption, design: .monospaced)).frame(width: 37, alignment: .trailing)
                } else {
                    Text("—  \(missingText)").font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            if let window {
                TimelineView(.everyMinute) { context in
                    Text(resetText(window.resetsAt, now: context.date))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }
    private func resetText(_ reset: Date?, now: Date) -> String {
        guard let reset else { return "Reset time —" }
        let minutes = max(0, Int(ceil(reset.timeIntervalSince(now) / 60)))
        if minutes == 0 { return "Reset due" }
        if minutes >= 1440 { return "Resets in \(minutes / 1440)d \((minutes % 1440) / 60)h" }
        if minutes >= 60 { return "Resets in \(minutes / 60)h \(minutes % 60)m" }
        return "Resets in \(minutes)m"
    }
}
