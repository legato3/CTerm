// ClaudeUsageView.swift
// CTerm
//
// Sidebar panel showing Claude Code token usage and cost from ~/.claude JSONL session files.

import SwiftUI
import Charts

struct ClaudeUsageView: View {
    @AppStorage(AppStorageKeys.dailyCostBudgetEnabled) private var budgetEnabled = false
    @AppStorage(AppStorageKeys.dailyCostBudget) private var budgetAmount = 10.0

    private var monitor: ClaudeUsageMonitor { ClaudeUsageMonitor.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !monitor.isLoaded {
                    loadingView
                } else {
                    todaySection
                    budgetSection
                    chartSection
                    modelSection
                    allTimeSection
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .onAppear { monitor.start() }
    }

    // MARK: - Loading

    private var loadingView: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading usage…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 40)
    }

    // MARK: - Today

    private var todaySection: some View {
        let t = monitor.today
        return VStack(alignment: .leading, spacing: 6) {
            Label("Today", systemImage: "sparkles")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                StatPill(
                    value: ClaudeUsageMonitor.formatTokens(t.totalTokens),
                    label: "tokens",
                    icon: "waveform"
                )
                StatPill(
                    value: String(format: "$%.3f", t.costUSD),
                    label: "cost",
                    icon: "dollarsign.circle"
                )
                StatPill(
                    value: "\(t.messageCount)",
                    label: "messages",
                    icon: "bubble.left.and.bubble.right"
                )
                StatPill(
                    value: "\(t.toolCallCount)",
                    label: "tool calls",
                    icon: "hammer"
                )
            }
        }
    }

    // MARK: - Budget

    private var budgetSection: some View {
        let cost = monitor.today.costUSD
        let fraction = budgetAmount > 0 ? min(cost / budgetAmount, 1.0) : 0.0
        let barColor: Color = fraction >= 1.0 ? .red : fraction >= 0.8 ? .orange : .green

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Daily Budget", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                Spacer()
                Toggle("", isOn: $budgetEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }

            if budgetEnabled {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Text("$")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                        TextField("10.00", value: $budgetAmount,
                                  format: .number.precision(.fractionLength(2)))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .frame(width: 70)
                        Spacer()
                        Text(String(format: "$%.3f / $%.2f", cost, budgetAmount))
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 5)
                            Capsule()
                                .fill(barColor.opacity(0.85))
                                .frame(width: geo.size.width * fraction, height: 5)
                                .animation(.easeInOut(duration: 0.3), value: fraction)
                        }
                    }
                    .frame(height: 5)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            }
        }
    }

    // MARK: - Chart

    private var chartSection: some View {
        let days = Array(monitor.recentDays.prefix(14).reversed())
        let useCost = days.contains { $0.costUSD > 0 }
        let maxValue: Double = useCost
            ? (days.map(\.costUSD).max() ?? 1)
            : Double(days.map(\.totalTokens).max() ?? 1)
        let todayKey = ClaudeUsageMonitor.isoDay(Date())

        return VStack(alignment: .leading, spacing: 6) {
            Label("Last 14 Days (\(useCost ? "cost" : "tokens"))", systemImage: "chart.bar")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            if days.isEmpty {
                Text("No activity in the last 14 days.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                Chart(days) { day in
                    BarMark(
                        x: .value("Date", shortDate(day.date)),
                        y: .value(useCost ? "Cost" : "Tokens",
                                  useCost ? day.costUSD : Double(day.totalTokens))
                    )
                    .foregroundStyle(
                        day.date == todayKey
                            ? Color.accentColor
                            : Color.accentColor.opacity(0.5)
                    )
                    .cornerRadius(3)
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { val in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel {
                            if useCost, let d = val.as(Double.self) {
                                Text(String(format: "$%.2f", d))
                                    .font(.system(size: 9)).foregroundStyle(.secondary)
                            } else if !useCost, let n = val.as(Int.self) {
                                Text(ClaudeUsageMonitor.formatTokens(n))
                                    .font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(days.count, 7))) { val in
                        AxisValueLabel {
                            if let s = val.as(String.self) {
                                Text(s).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...(maxValue + maxValue / 5))
                .frame(height: 90)
            }
        }
    }

    // MARK: - Model Breakdown

    private var modelSection: some View {
        let models = monitor.modelBreakdown
        guard !models.isEmpty else { return AnyView(EmptyView()) }
        let maxCost = models.first?.costUSD ?? 0

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                Label("Models (30d)", systemImage: "cpu")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                VStack(spacing: 4) {
                    ForEach(models) { m in
                        ModelRow(activity: m, maxCost: maxCost)
                    }
                }
            }
        )
    }

    // MARK: - All Time

    private var allTimeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("All Time", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            VStack(spacing: 3) {
                AllTimeRow(label: "Sessions", value: "\(monitor.totalSessions)")
                AllTimeRow(label: "Messages", value: "\(monitor.totalMessages)")
                if let first = monitor.firstSessionDate {
                    AllTimeRow(
                        label: "Since",
                        value: first.formatted(.dateTime.month(.abbreviated).day().year())
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func shortDate(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return iso }
        return "\(month)/\(day)"
    }
}

// MARK: - Sub-views

private struct StatPill: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

private struct ModelRow: View {
    let activity: ModelActivity
    let maxCost: Double

    private var fraction: Double {
        maxCost > 0 ? min(activity.costUSD / maxCost, 1.0) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(activity.shortName)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)
                Spacer()
                if activity.costUSD > 0 {
                    Text(String(format: "$%.3f", activity.costUSD))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Text(ClaudeUsageMonitor.formatTokens(activity.totalTokens))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 4)
                    Capsule()
                        .fill(Color.accentColor.opacity(0.7))
                        .frame(width: geo.size.width * fraction, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 4)
    }
}

private struct AllTimeRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .padding(.vertical, 2)
    }
}
