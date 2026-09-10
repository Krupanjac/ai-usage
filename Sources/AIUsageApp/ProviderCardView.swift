import SwiftUI
import AIUsageCore

struct ProviderCardView: View {
    var state: ProviderState
    private var tint: Color { state.provider == .claude ? .orange : .teal }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(state.provider.name).font(.system(.subheadline, weight: .semibold))
                Spacer()
                if let plan = state.quota?.planType { Text(plan).font(.caption).foregroundStyle(.secondary) }
                if state.isRefreshing { ProgressView().controlSize(.mini) }
            }
            TimelineView(.everyMinute) { context in
                Text(statusText(now: context.date)).font(.caption2).foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            QuotaBarView(title: "5h", window: state.quota?.fiveHour, tint: tint, missingText: missingText)
            QuotaBarView(title: "Week", window: state.quota?.weekly, tint: tint, missingText: missingText)
            ForEach(state.quota?.extra ?? []) { extra in
                QuotaBarView(title: extra.name, window: extra.window, tint: tint, missingText: missingText)
            }
        }
        .padding(12)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
    private var missingText: String { state.quota == nil ? "Usage unavailable" : "Not reported for this plan" }
    private var statusColor: Color {
        switch state.status {
        case .expired, .signIn, .failed, .rateLimited: .orange
        default: .secondary
        }
    }
    private func statusText(now: Date) -> String {
        let stamp = state.quota.map { $0.asOf.formatted(date: .omitted, time: .shortened) }
        let cached = stamp.map { " · cached \($0)" } ?? ""
        switch state.status {
        case .loading: return "Reading usage…"
        case .notInstalled: return "Not installed"
        case .signIn: return "Run `\(state.provider.command)` to sign in\(cached)"
        case .expired: return "Token expired · run `\(state.provider.command)` to sign in again\(cached)"
        case .offline: return "Offline\(cached)"
        case .rateLimited(let until): return "Rate limited · retry \(until.formatted(date: .omitted, time: .shortened))\(cached)"
        case .failed: return "Quota unavailable\(cached)"
        case .available:
            guard let quota = state.quota else { return state.isRefreshing ? "Refreshing…" : "Waiting for usage" }
            if quota.source == .network, now.timeIntervalSince(quota.asOf) < 360 { return "Live" }
            let date = Calendar.autoupdatingCurrent.isDateInToday(quota.asOf)
                ? quota.asOf.formatted(date: .omitted, time: .shortened)
                : quota.asOf.formatted(date: .abbreviated, time: .shortened)
            return "As of \(date)" + (quota.source == .localLog ? " · local session" : " · cached")
        }
    }
}
