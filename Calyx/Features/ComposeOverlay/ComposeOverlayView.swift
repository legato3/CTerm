// ComposeOverlayView.swift
// Calyx
//
// Transparent text editor overlay for composing terminal input.

import AppKit
import os

private let logger = Logger(subsystem: "com.calyx.terminal", category: "ComposeOverlay")

@MainActor
class ComposeOverlayView: NSView {

    // MARK: - Properties

    private let scrollView = NSScrollView()
    private(set) var textView = NSTextView()
    private let placeholderLabel = NSTextField(labelWithString: "Compose...")

    var onSend: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    // MARK: - Initializers

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - View Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        window?.makeFirstResponder(textView)
    }

    // MARK: - Setup

    private func setupView() {
        wantsLayer = true

        // Text view setup
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self

        // Scroll view
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        // Placeholder
        placeholderLabel.textColor = .placeholderTextColor
        placeholderLabel.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        placeholderLabel.isBordered = false
        placeholderLabel.drawsBackground = false
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
        ])

        setAccessibilityIdentifier(AccessibilityID.Compose.container)
        textView.setAccessibilityIdentifier(AccessibilityID.Compose.textView)
    }

    // MARK: - Key Handling (overrides on the view itself for when textView doesn't handle)

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Cmd+Shift+E toggle (even when textView has focus)
        if event.modifierFlags.contains([.command, .shift]),
           event.charactersIgnoringModifiers?.lowercased() == "e" {
            onDismiss?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - NSResponder overrides (called by NSTextView delegate forwarding)

    override func insertNewline(_ sender: Any?) {
        // Trim only for emptiness check; send raw text to preserve user formatting.
        let trimmed = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend?(textView.string)
    }

    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        textView.insertNewlineIgnoringFieldEditor(sender)
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    // MARK: - Placeholder

    private func updatePlaceholder() {
        placeholderLabel.isHidden = !textView.string.isEmpty
    }
}

// MARK: - NSTextViewDelegate

extension ComposeOverlayView: NSTextViewDelegate {

    func textDidChange(_ notification: Notification) {
        updatePlaceholder()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            insertNewline(nil)
            return true
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            insertNewlineIgnoringFieldEditor(nil)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancelOperation(nil)
            return true
        default:
            return false
        }
    }
}
