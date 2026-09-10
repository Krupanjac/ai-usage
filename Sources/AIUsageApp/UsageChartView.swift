import SwiftUI
import Charts
import AIUsageCore

struct UsageChartView: View {
    @Bindable var store: UsageStore
    @State private var selectedDate: Date?
    private let colors: [Color] = [.blue, .teal, .purple, .orange]
    var body: some View {
        TimelineView(.everyMinute) { context in
            let series = store.chartSeries(now: context.date)
            let totals = series.reduce(TokenTotals()) { $0 + $1.totals }
            VStack(alignment: .leading, spacing: 10) {
                Text("Token history").font(.system(.subheadline, weight: .semibold))
                HStack(spacing: 12) {
                    Picker("Provider", selection: $store.selectedProvider) {
                        Text("Claude").tag(Provider.claude)
                        Text("Codex").tag(Provider.codex)
                    }.frame(width: 145).accessibilityLabel("History provider")
                    Picker("Date range", selection: $store.chartRange) {
                        ForEach(ChartRange.allCases) { range in Text(range.rawValue).tag(range) }
                    }.accessibilityLabel("History date range")
                }.pickerStyle(.segmented).controlSize(.small).labelsHidden()
                Chart {
                    ForEach(series) { day in
                        ForEach(TokenKind.allCases) { kind in
                            BarMark(x: .value("Date", day.date, unit: store.chartRange.isHourly ? .hour : .day),
                                    y: .value("Tokens", day.totals[kind]))
                                .foregroundStyle(by: .value("Token kind", kind.rawValue))
                                .accessibilityLabel("\(day.date.formatted(date: .abbreviated, time: store.chartRange.isHourly ? .shortened : .omitted)), \(kind.rawValue)")
                                .accessibilityValue("\(day.totals[kind]) tokens")
                        }
                    }
                    if let selected = selectedPoint(in: series) {
                        RuleMark(x: .value("Selected", selected.date, unit: store.chartRange.isHourly ? .hour : .day))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                }
                .chartForegroundStyleScale(domain: TokenKind.allCases.map(\.rawValue), range: colors)
                .chartLegend(.hidden)
                .chartXSelection(value: $selectedDate)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: store.chartRange.isHourly ? .dateTime.hour() : .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel { if let tokens = value.as(Int.self) { Text(tokens.compactTokens) } }
                    }
                }
                .chartYScale(domain: 0...max(1, series.map { $0.totals.total }.max() ?? 1))
                .frame(height: 116)
                .overlay {
                    HistoryEmptyState(store: store, total: totals.total)
                }
                HStack(spacing: 10) {
                    ForEach(Array(TokenKind.allCases.enumerated()), id: \.element.id) { index, kind in
                        HStack(spacing: 3) {
                            Circle().fill(colors[index]).frame(width: 5, height: 5)
                            Text(kind.rawValue).font(.system(size: 9))
                        }
                    }
                }.foregroundStyle(.secondary)
                if let selected = selectedPoint(in: series) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selected.date.formatted(date: .abbreviated, time: store.chartRange.isHourly ? .shortened : .omitted)).fontWeight(.medium)
                        Text("\(selected.totals.total.formatted()) tokens · \(selected.totals.output.compactTokens) output")
                    }.font(.caption2)
                } else {
                    Text("\(totals.total.compactTokens) tokens · \(totals.output.compactTokens) output · \((totals.total / store.chartRange.count).compactTokens)/\(store.chartRange.isHourly ? "hr" : "day") avg")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HistoryIndexStatus(store: store)
            }
        }
        .onChange(of: store.selectedProvider) { selectedDate = nil }
        .onChange(of: store.chartRange) { selectedDate = nil }
    }
    private func selectedPoint(in series: [DailyUsage]) -> DailyUsage? {
        guard let selectedDate else { return nil }
        let component: Calendar.Component = store.chartRange.isHourly ? .hour : .day
        return series.first { Calendar.autoupdatingCurrent.isDate($0.date, equalTo: selectedDate, toGranularity: component) }
    }
}

// Keep progress observation out of the chart body: a rebuild should update its progress bar,
// without repeatedly constructing Charts' marks, axes, and accessibility tree for every file.
private struct HistoryIndexStatus: View {
    var store: UsageStore
    var body: some View {
        if store.indexProgress.isRunning {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: store.indexProgress.fraction)
                Text("\(store.indexProgress.isRebuilding ? "Indexing history" : "Updating history") · \(store.indexProgress.completedFiles)/\(store.indexProgress.totalFiles) files")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        if let message = store.indexMessage { Text(message).font(.caption2).foregroundStyle(.secondary) }
    }
}

private struct HistoryEmptyState: View {
    var store: UsageStore
    var total: Int
    var body: some View {
        if total == 0 && !store.indexProgress.isRunning {
            Text("No recorded tokens in this range").font(.caption).foregroundStyle(.secondary)
                .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

extension Int {
    var compactTokens: String { Double(self).formatted(.number.notation(.compactName).precision(.fractionLength(0...1))) }
}
