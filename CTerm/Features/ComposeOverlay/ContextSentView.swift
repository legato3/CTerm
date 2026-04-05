// ContextSentView.swift
// CTerm
//
// Collapsed disclosure triangle showing the enriched context that was
// actually sent to the agent. Lets the user see exactly what the agent
// was told, building trust and predictability.

import SwiftUI

struct ContextSentView: View {
    let enrichedPrompt: String
    @State private var isExpanded = false

    /// Extract just the context block from the enriched prompt.
    private var contextBlock: String? {
        guard let start = enrichedPrompt.range(of: "<cterm_agent_context>"),
              let end = enrichedPrompt.range(of: "</cterm_agent_context>") else {
            return nil
        }
        return String(enrichedPrompt[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var userPrompt: String {
        if let range = enrichedPrompt.range(of: "\n\n<cterm_agent_context>") {
            return String(enrichedPrompt[..<range.lowerBound])
        }
        return enrichedPrompt
    }

    var body: some View {
        if let context = contextBlock {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8))
                        Text("Context sent")
                            .font(.system(size: 9, design: .rounded))
                        Spacer()
                    }
                    .foregroundStyle(.tertiary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Text(context)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.quaternary)
                        .lineLimit(30)
                        .textSelection(.enabled)
                        .padding(6)
                        .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }
}
