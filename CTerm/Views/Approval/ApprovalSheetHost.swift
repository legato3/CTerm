// ApprovalSheetHost.swift
// CTerm
//
// View modifier that mounts the approval sheet whenever
// ApprovalPresenter.shared has a pending context. Applied once per window.

import SwiftUI

struct ApprovalSheetHost: ViewModifier {
    @State private var presenter = ApprovalPresenter.shared

    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: Binding(
                    get: { presenter.pendingContext != nil },
                    set: { newValue in if !newValue { presenter.dismiss() } }
                )
            ) {
                if let context = presenter.pendingContext {
                    ApprovalSheet(
                        context: context,
                        hardStop: presenter.pendingHardStop,
                        onResolve: { answer, scope in
                            presenter.resolve(answer: answer, scope: scope)
                        },
                        onDismiss: {
                            presenter.dismiss()
                        }
                    )
                }
            }
    }
}

extension View {
    /// Attach the approval sheet to this view. Use on the root window content.
    func hostsApprovalSheet() -> some View {
        modifier(ApprovalSheetHost())
    }
}
