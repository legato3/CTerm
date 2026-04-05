// AmbientSuggestionBadge.swift
// CTerm
//
// Subtle notification badge on the agent input bar when ambient suggestions
// are available. Expands to show suggestions on click.

import SwiftUI

struct AmbientSuggestionBadge: View {
    let suggestions: [AmbientSuggestion]
    var onAct: (AmbientSuggestion) -> Void
    var onDismiss: (UUID) -> Void
    var onDismissAll: () -> Void

    @State private var isExpanded = false

    var body: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .trailing, spacing: 4) {
                if isExpanded {
                    expandedView
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                        Text("\(suggestions.count)")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(suggestions) { suggestion in
                HStack(spacing: 6) {
                    Image(systemName: suggestion.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(suggestion.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        onAct(suggestion)
                    } label: {
                        Text("Act")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)

                    Button {
                        onDismiss(suggestion.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            if suggestions.count > 1 {
                Button("Dismiss all") {
                    onDismissAll()
                    withAnimation { isExpanded = false }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .frame(maxWidth: 280)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}
