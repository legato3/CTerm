// MemoryToastView.swift
// CTerm
//
// Floating toast that appears when agent memory is written.
// Shows briefly at the bottom of the terminal area, then fades out.

import SwiftUI

struct MemoryToastView: View {
    let toast: MemoryToast
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: toast.isNew ? "brain.head.profile" : "arrow.triangle.2.circlepath")
                .font(.system(size: 10))
                .foregroundStyle(.purple)

            Text(toast.displayText)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
