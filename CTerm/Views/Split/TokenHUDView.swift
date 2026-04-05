// TokenHUDView.swift
// CTerm
//
// Phase 9: Token Budget HUD — a subtle pill overlay in the top-left corner of
// each terminal pane, showing context window usage and today's Claude cost.
// Auto-hides when no context data has been detected yet.

import SwiftUI

// MARK: - TokenHUDView

struct TokenHUDView: View {
    let paneID: UUID
    @State private var store: PaneUsageStore = .shared
    @State private var usageMonitor: ClaudeUsageMonitor = .shared

    private var snapshot: PaneUsageSnapshot? {
        store.snapshots[paneID]
    }

    private var contextFraction: Double? {
        snapshot?.contextFraction
    }

    var body: some View {
        Group {
            if let fraction = contextFraction {
                pill(fraction: fraction)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            // No snapshot or fraction → render nothing (zero-size)
        }
        .animation(.easeInOut(duration: 0.3), value: contextFraction != nil)
    }

    // MARK: - Pill

    @ViewBuilder
    private func pill(fraction: Double) -> some View {
        let level = urgencyLevel(fraction)
        HStack(spacing: 5) {
            // Arc progress indicator
            ArcProgress(fraction: fraction, color: level.arcColor)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(level.textColor)

                if let cost = todayCost {
                    Text(cost)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(level.borderColor, lineWidth: level == .critical ? 1.5 : 0.5)
                }
        }
        .shadow(color: level.glowColor, radius: level == .normal ? 0 : 6)
    }

    // MARK: - Cost

    private var todayCost: String? {
        let cost = usageMonitor.today.costUSD
        guard cost > 0 else { return nil }
        if cost < 0.01 { return "<$0.01" }
        return String(format: "$%.2f today", cost)
    }

    // MARK: - Urgency

    enum UrgencyLevel: Equatable {
        case normal      // < 70%
        case warning     // 70–85%
        case critical    // > 85%

        var arcColor: Color {
            switch self {
            case .normal:   return .blue
            case .warning:  return .orange
            case .critical: return .red
            }
        }

        var textColor: Color {
            switch self {
            case .normal:   return .primary
            case .warning:  return .orange
            case .critical: return .red
            }
        }

        var borderColor: Color {
            switch self {
            case .normal:   return Color.white.opacity(0.15)
            case .warning:  return Color.orange.opacity(0.5)
            case .critical: return Color.red.opacity(0.7)
            }
        }

        var glowColor: Color {
            switch self {
            case .normal:   return .clear
            case .warning:  return Color.orange.opacity(0.25)
            case .critical: return Color.red.opacity(0.4)
            }
        }
    }

    private func urgencyLevel(_ fraction: Double) -> UrgencyLevel {
        if fraction >= 0.85 { return .critical }
        if fraction >= 0.70 { return .warning }
        return .normal
    }
}

// MARK: - ArcProgress

/// Thin circular arc progress indicator (like a watch complication).
private struct ArcProgress: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: CGFloat(min(fraction, 1.0)))
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)
        }
    }
}
