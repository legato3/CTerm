// SplitDividerView.swift
// CTerm
//
// NSView subclass for the split divider line with drag handling.

import AppKit

@MainActor
class SplitDividerView: NSView {

    let direction: SplitDirection
    var onRatioChange: ((Double) -> Void)?

    private var isDragging = false
    private var dragStartPoint: CGPoint = .zero
    private var dragStartRatio: Double = 0

    private let visibleThickness: CGFloat = 1
    private let hitAreaThickness: CGFloat = 7

    init(direction: SplitDirection) {
        self.direction = direction
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.separatorColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Layout

    var thickness: CGFloat { hitAreaThickness }

    override var isFlipped: Bool { true }

    // MARK: - Cursor

    override func resetCursorRects() {
        let cursor: NSCursor = direction == .horizontal ? .resizeLeftRight : .resizeUpDown
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        dragStartPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        guard let superview else { return }

        let currentPoint = convert(event.locationInWindow, from: nil)
        let parentSize = superview.bounds.size

        let delta: CGFloat
        let totalSize: CGFloat

        switch direction {
        case .horizontal:
            delta = currentPoint.x - dragStartPoint.x
            totalSize = parentSize.width
        case .vertical:
            delta = currentPoint.y - dragStartPoint.y
            totalSize = parentSize.height
        }

        guard totalSize > 0 else { return }
        let ratioDelta = delta / totalSize
        onRatioChange?(ratioDelta)
        dragStartPoint = currentPoint
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }
}
