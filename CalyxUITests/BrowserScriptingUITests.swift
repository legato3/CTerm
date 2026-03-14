import XCTest

final class BrowserScriptingUITests: CalyxUITestCase {

    private let outputFile = "/tmp/calyx-e2e-output.txt"

    private func paletteRun(_ query: String, buttonTitle: String = "OK") {
        openCommandPaletteViaMenu()
        let sf = app.descendants(matching: .any)
            .matching(identifier: "calyx.commandPalette.searchField").firstMatch
        XCTAssertTrue(waitFor(sf), "palette search field not found")
        sf.typeText(query)
        Thread.sleep(forTimeInterval: 0.5)
        sf.typeKey(.enter, modifierFlags: [])
        let dlg = app.dialogs.firstMatch
        if dlg.waitForExistence(timeout: 5) {
            dlg.buttons[buttonTitle].click()
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Paste a command into the terminal via Cmd+V (bypasses IME), run it, read output from file.
    private func terminalExec(_ command: String) -> String {
        try? FileManager.default.removeItem(atPath: outputFile)

        Thread.sleep(forTimeInterval: 1) // wait for shell prompt
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("\(command) > \(outputFile) 2>&1", forType: .string)
        app.typeKey("v", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
        app.typeKey(.return, modifierFlags: [])

        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.5)
            if FileManager.default.fileExists(atPath: outputFile),
               let content = try? String(contentsOfFile: outputFile, encoding: .utf8),
               !content.isEmpty {
                return content
            }
        }
        return (try? String(contentsOfFile: outputFile, encoding: .utf8)) ?? "(no output)"
    }

    func test_mcpToolsWorkEndToEnd() {
        // 1. Enable browser scripting
        paletteRun("Browser Scripting", buttonTitle: "Enable")

        // 2. Enable IPC
        paletteRun("AI Agent IPC", buttonTitle: "OK")
        Thread.sleep(forTimeInterval: 1)

        // 3. Open browser tab
        menuAction("File", item: "New Browser Tab")
        let dlg = app.dialogs.firstMatch
        XCTAssertTrue(dlg.waitForExistence(timeout: 5), "URL dialog missing")
        let tf = dlg.textFields.firstMatch
        if tf.waitForExistence(timeout: 2) { tf.click(); tf.typeText("https://example.com") }
        dlg.buttons["Open"].click()

        let toolbar = app.descendants(matching: .any)
            .matching(identifier: "calyx.browser.toolbar").firstMatch
        XCTAssertTrue(waitFor(toolbar, timeout: 15), "browser toolbar missing")
        Thread.sleep(forTimeInterval: 3)

        // 4. Switch back to terminal tab (Cmd+1)
        app.typeKey("1", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 1)

        // 5. calyx browser list — get tab_id
        let list = terminalExec("calyx browser list")
        XCTAssertTrue(list.contains("example.com"), "browser list should contain example.com, got: \(list)")

        // Extract tab_id from JSON output
        let tabId: String = {
            guard let data = list.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tabs = json["tabs"] as? [[String: Any]],
                  let first = tabs.first,
                  let id = first["id"] as? String else { return "" }
            return id
        }()
        XCTAssertFalse(tabId.isEmpty, "should extract tab_id from list output")

        // 6. calyx browser get-text h1 --tab-id <id>
        let getText = terminalExec("calyx browser get-text h1 --tab-id \(tabId)")
        XCTAssertTrue(getText.contains("Example Domain"), "get-text should contain Example Domain, got: \(getText)")

        // 7. calyx browser snapshot --tab-id <id>
        let snap = terminalExec("calyx browser snapshot --tab-id \(tabId)")
        XCTAssertFalse(snap.isEmpty, "snapshot should not be empty")

        // 8. calyx browser click a --tab-id <id>
        let click = terminalExec("calyx browser click a --tab-id \(tabId)")
        XCTAssertFalse(click.contains("Error"), "click should not error, got: \(click)")

        // 9. calyx browser eval --tab-id <id>
        let eval = terminalExec("calyx browser eval 'document.title' --tab-id \(tabId)")
        XCTAssertFalse(eval.isEmpty, "eval should return something, got: \(eval)")
    }

    func test_toolsBlockedWithoutScripting() {
        // Only enable IPC, NOT scripting
        paletteRun("AI Agent IPC", buttonTitle: "OK")
        Thread.sleep(forTimeInterval: 1)

        let result = terminalExec("calyx browser list")
        XCTAssertTrue(result.contains("not enabled") || result.contains("Error"),
                      "should be blocked without scripting: \(result)")
    }
}
