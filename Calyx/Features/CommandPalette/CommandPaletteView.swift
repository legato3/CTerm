// CommandPaletteView.swift
// Calyx
//
// Overlay panel at top of window for command palette UI.

import AppKit
import os

private let logger = Logger(subsystem: "com.calyx.terminal", category: "CommandPalette")

@MainActor
class CommandPaletteView: NSView {

    private let registry: CommandRegistry
    private let searchField = NSTextField()
    private let resultsScrollView = NSScrollView()
    private let resultsTableView = NSTableView()

    private var filteredCommands: [Command] = []
    private var selectedIndex = 0

    var onDismiss: (() -> Void)?

    init(registry: CommandRegistry) {
        self.registry = registry
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setupView() {
        wantsLayer = true
        GlassEffectHelper.applyBackground(to: self)

        searchField.placeholderString = "Type a command..."
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 16)
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchField)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        column.title = ""
        resultsTableView.addTableColumn(column)
        resultsTableView.headerView = nil
        resultsTableView.selectionHighlightStyle = .regular

        resultsScrollView.documentView = resultsTableView
        resultsScrollView.hasVerticalScroller = true
        resultsScrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(resultsScrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            searchField.heightAnchor.constraint(equalToConstant: 32),

            resultsScrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 4),
            resultsScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            resultsScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            resultsScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        updateResults()
    }

    @objc private func searchChanged(_ sender: NSTextField) {
        updateResults()
    }

    private func updateResults() {
        let query = searchField.stringValue
        filteredCommands = registry.search(query: query)
        selectedIndex = 0
        resultsTableView.reloadData()
    }

    func executeSelected() {
        guard filteredCommands.indices.contains(selectedIndex) else { return }
        let command = filteredCommands[selectedIndex]
        registry.recordUsage(command.id)
        onDismiss?()
        command.handler()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 0x7E: // Up arrow
            if selectedIndex > 0 {
                selectedIndex -= 1
                resultsTableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
            }
        case 0x7D: // Down arrow
            if selectedIndex < filteredCommands.count - 1 {
                selectedIndex += 1
                resultsTableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
            }
        case 0x24: // Return
            executeSelected()
        case 0x35: // Escape
            onDismiss?()
        default:
            super.keyDown(with: event)
        }
    }
}
