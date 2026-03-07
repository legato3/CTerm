import AppKit
import GhosttyKit
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.calyx.terminal",
    category: "SettingsWindowController"
)

@MainActor
class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        setupContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func setupContent() {
        guard let window = self.window,
              let contentView = window.contentView else { return }

        let label = NSTextField(labelWithString: "Settings will be available in a future update.\nUse the ghostty configuration file for now.")
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])

        // Add "Open Config" button
        let button = NSButton(title: "Open Config File", target: self, action: #selector(openConfigFile(_:)))
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(button)

        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 16),
        ])
    }

    func showSettings() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openConfigFile(_ sender: Any?) {
        if let app = GhosttyAppController.shared.app {
            GhosttyFFI.appOpenConfig(app)
        }
    }

    @objc func reloadConfig() {
        // Ghostty reloads config automatically via file watcher
        // This is a manual trigger if needed
        logger.info("Config reload requested")
    }
}
