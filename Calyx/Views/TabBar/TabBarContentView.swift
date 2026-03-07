// TabBarContentView.swift
// Calyx
//
// SwiftUI horizontal tab strip for the active tab group.

import SwiftUI

struct TabBarContentView: View {
    let tabs: [Tab]
    let activeTabID: UUID?
    var onTabSelected: ((UUID) -> Void)?
    var onNewTab: (() -> Void)?
    var onCloseTab: ((UUID) -> Void)?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(tabs) { tab in
                        TabItemButton(
                            tab: tab,
                            isActive: tab.id == activeTabID,
                            onSelected: { onTabSelected?(tab.id) },
                            onClose: { onCloseTab?(tab.id) }
                        )
                    }
                }
            }

            Spacer(minLength: 0)

            Button(action: { onNewTab?() }) {
                Image(systemName: "plus")
                    .font(.caption)
            }
            .modifier(GlassButtonModifier(reduceTransparency: reduceTransparency))
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 4)
        .frame(height: 32)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onNewTab?() }
        .modifier(TabBarBackgroundModifier(reduceTransparency: reduceTransparency))
    }
}

private struct GlassButtonModifier: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.buttonStyle(.plain)
        } else {
            content.buttonStyle(.glass)
        }
    }
}

private struct TabBarBackgroundModifier: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor))
        } else {
            content.glassEffect(.regular, in: .rect)
        }
    }
}

private struct TabItemButton: View {
    let tab: Tab
    let isActive: Bool
    var onSelected: (() -> Void)?
    var onClose: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: { onSelected?() }) {
                Text(tab.title)
                    .lineLimit(1)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                    .padding(.trailing, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { onClose?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .opacity(isHovering || isActive ? 1 : 0)
            .allowsHitTesting(isHovering || isActive)
        }
        .frame(minWidth: 96, idealWidth: 140, maxWidth: 180)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4).fill(
                isActive ? Color.accentColor.opacity(0.12) :
                isHovering ? Color.white.opacity(0.06) : Color.clear
            )
        )
        .onHover { isHovering = $0 }
    }
}
