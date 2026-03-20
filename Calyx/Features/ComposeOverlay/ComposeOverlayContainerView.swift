// ComposeOverlayContainerView.swift
// Calyx
//
// NSViewRepresentable wrapper for the compose overlay.

import SwiftUI

struct ComposeOverlayContainerView: NSViewRepresentable {
    var onSend: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    func makeNSView(context: Context) -> ComposeOverlayView {
        let view = ComposeOverlayView()
        view.onSend = onSend
        view.onDismiss = onDismiss
        return view
    }

    func updateNSView(_ nsView: ComposeOverlayView, context: Context) {
        nsView.onSend = onSend
        nsView.onDismiss = onDismiss
    }
}
