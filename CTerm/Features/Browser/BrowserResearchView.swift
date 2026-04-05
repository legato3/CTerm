// BrowserResearchView.swift
// CTerm
//
// SwiftUI view showing the live browser research step log.
// Displays each step with status, timing, and extracted findings.
// Embedded in the agent plan sidebar when a browser research session is active.

import SwiftUI

struct BrowserResearchView: View {
    let session: BrowserResearchSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .foregroundStyle(.blue)
                Text("Browser Research")
                    .font(.headline)
                Spacer()
                if !session.isComplete {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            // Goal
            Text(session.goal.prefix(80))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()

            // Step log
            ForEach(session.logEntries, id: \.id) { entry in
                BrowserResearchStepRow(entry: entry)
            }

            // Findings
            if !session.findings.isEmpty {
                Divider()
                Text("Findings (\(session.findings.count))")
                    .font(.subheadline.weight(.medium))
                ForEach(session.findings) { finding in
                    BrowserFindingRow(finding: finding)
                }
            }

            // Summary
            if let summary = session.summary {
                Divider()
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(10)
    }
}

// MARK: - Step Row

struct BrowserResearchStepRow: View {
    let entry: BrowserResearchLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusIcon
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                if let command = entry.command {
                    Text(command.prefix(60))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if let output = entry.output, entry.status == .failed {
                    Text(output.prefix(100))
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let duration = durationText {
                Text(duration)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch entry.status {
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case .skipped:
            Image(systemName: "forward.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private var durationText: String? {
        guard let completed = entry.completedAt else { return nil }
        let ms = Int(completed.timeIntervalSince(entry.startedAt) * 1000)
        return ms < 1000 ? "\(ms)ms" : "\(ms / 1000)s"
    }
}

// MARK: - Finding Row

struct BrowserFindingRow: View {
    let finding: BrowserFinding

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(.cyan)
                        .font(.caption)
                    Text(finding.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    if !finding.url.isEmpty && finding.url != "unknown" {
                        Text(finding.url)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                    }
                    Text(finding.content.prefix(500))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(12)
                        .textSelection(.enabled)
                }
                .padding(.leading, 22)
            }
        }
        .padding(.vertical, 2)
    }
}
