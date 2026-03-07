// GlassEffectHelper.swift
// Calyx
//
// Isolates all macOS 26 Liquid Glass API usage behind @available guards.
// No Glass types appear in non-guarded code paths.

import AppKit

enum GlassEffectHelper {

    static var isGlassAvailable: Bool {
        if #available(macOS 26.0, *) {
            return !reducedTransparency
        }
        return false
    }

    static var reducedTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    @available(macOS 26.0, *)
    static func applyGlassBackground(to view: NSView) {
        guard !reducedTransparency else {
            applyFallbackBackground(to: view, color: .windowBackgroundColor)
            return
        }
        // macOS 26 Glass API: NSGlassContainerView or similar
        // For now, use a vibrancy effect as the best available approximation
        let effect = NSVisualEffectView(frame: view.bounds)
        effect.material = .headerView
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        effect.autoresizingMask = [.width, .height]
        view.addSubview(effect, positioned: .below, relativeTo: nil)
    }

    static func applyFallbackBackground(to view: NSView, color: NSColor) {
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
    }

    static func applyBackground(to view: NSView) {
        if isGlassAvailable {
            if #available(macOS 26.0, *) {
                applyGlassBackground(to: view)
            }
        } else {
            applyFallbackBackground(to: view, color: .windowBackgroundColor)
        }
    }
}
