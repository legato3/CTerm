// AgentInputBar.swift
// CTerm
//
// Always-visible thin input bar at the bottom of the terminal area.
// Provides a natural-language-first entry point for agent interactions
// without requiring ⌘K to open the full compose overlay.
// Shows ActiveAI suggestion chips inline as pill buttons.

import SwiftUI

struct AgentInputBar: View {
    @Binding var text: String
    let suggestions: [ActiveAISuggestion]
    let isAgentRunning: Bool
    let planStore: AgentPlanStore?
    var onSubmit: (String) -> Void
    var onSuggestionTapped: (ActiveAISuggestion) -> Void
    var onExpandCompose: () -> Void

    @State private var isFocused = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Suggestion chips
            if !suggestions.isEmpty && !isAgentRunning {
                suggestionChips
            }

            // Plan view (inline when active)
            if let store = planStore, let plan = store.activePlan, !plan.status.isTerminal {
                AgentPlanView(
                    plan: plan,
                    onApproveStep: { id in store.approveStep(id: id) },
                    onApproveAll: { store.approveAllPending() },
                    onSkipStep: { id in store.skipStep(id: id) },
                    onStop: { store.stopPlan() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Input row
            HStack(spacing: 8) {
                Image(systemName: isAgentRunning ? "sparkles" : "terminal")
                    .font(.system(size: 12))
                    .foregroundStyle(isAgentRunning ? .blue : .secondary)
                    .symbolEffect(.pulse, isActive: isAgentRunning)

                TextField("Ask CTerm anything…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($fieldFocused)
                    .onSubmit {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSubmit(trimmed)
                        text = ""
                    }

                if !text.isEmpty {
                    Button {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSubmit(trimmed)
                        text = ""
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                }

                Button {
                    onExpandCompose()
                } label: {
                    Image(systemName: "rectangle.expand.vertical")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Open full compose overlay (⌘K)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(suggestions) { suggestion in
                    Button {
                        onSuggestionTapped(suggestion)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: suggestion.icon)
                                .font(.system(size: 9))
                            Text(suggestion.prompt)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(chipBackground(for: suggestion.kind))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    private func chipBackground(for kind: ActiveAISuggestion.Kind) -> some ShapeStyle {
        switch kind {
        case .fix:           return AnyShapeStyle(.red.opacity(0.1))
        case .explain:       return AnyShapeStyle(.blue.opacity(0.1))
        case .nextStep:      return AnyShapeStyle(.green.opacity(0.1))
        case .continueAgent: return AnyShapeStyle(.purple.opacity(0.1))
        case .custom:        return AnyShapeStyle(.secondary.opacity(0.1))
        }
    }
}
