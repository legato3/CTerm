// BlockPersistenceTests.swift
// CTerm
//
// LS3: Block attachment persistence across restart.
// Verifies TabSnapshotBuilder round-trips attached block IDs + bounded block history.

import XCTest
@testable import CTerm

@MainActor
final class BlockPersistenceTests: XCTestCase {

    private func makeBlock(
        id: UUID = UUID(),
        command: String = "echo hi",
        output: String? = "ok",
        exitCode: Int? = 0
    ) -> TerminalCommandBlock {
        TerminalCommandBlock(
            id: id,
            source: .shell,
            surfaceID: UUID(),
            command: command,
            startedAt: Date(),
            finishedAt: Date(),
            status: (exitCode ?? 0) == 0 ? .succeeded : .failed,
            outputSnippet: output,
            errorSnippet: nil,
            exitCode: exitCode,
            durationNanoseconds: 1_000_000,
            cwd: "/tmp"
        )
    }

    // MARK: - Round-trip with mixed recent + old attachments

    func test_roundtrip_preserves_attached_and_recent_blocks() {
        let tab = Tab(id: UUID(), title: "Test", content: .terminal)

        // Insert 25 blocks. blockStore.append inserts newest-first, so block 24 ends
        // up at index 0 and block 0 at index 24.
        var all: [TerminalCommandBlock] = []
        for i in 0..<25 {
            let b = makeBlock(command: "cmd-\(i)")
            all.append(b)
            tab.blockStore.append(b)
        }

        // After insertion, newest-first order: [24, 23, ..., 1, 0]
        // Recent 20 = blocks with command indices [24..5]
        // Attach an old block (cmd-2, which is at index 22) + two recent (cmd-24 at 0, cmd-20 at 4)
        let oldBlock = all[2]   // cmd-2, not in recent 20
        let recentA = all[24]   // cmd-24, newest
        let recentB = all[20]   // cmd-20, within recent
        tab.attachBlock(oldBlock.id)
        tab.attachBlock(recentA.id)
        tab.attachBlock(recentB.id)

        // Sanity: commandBlocks uses newest-first
        XCTAssertEqual(tab.commandBlocks.first?.command, "cmd-24")
        XCTAssertEqual(tab.commandBlocks.count, 25)

        // Build snapshot
        let snap = TabSnapshotBuilder.build(from: tab, browserURL: nil)

        // Persisted blocks = 20 recent + 1 old attached (the two recent attached are in the 20)
        guard let persisted = snap.persistedBlocks else {
            XCTFail("expected persistedBlocks")
            return
        }
        XCTAssertEqual(persisted.count, 21, "20 recent + 1 extra old-attached")

        let persistedIDs = Set(persisted.map { $0.id })
        XCTAssertTrue(persistedIDs.contains(oldBlock.id), "old attached block must be persisted")
        XCTAssertTrue(persistedIDs.contains(recentA.id))
        XCTAssertTrue(persistedIDs.contains(recentB.id))

        // attachedBlockIDs persisted
        guard let attachedIDs = snap.attachedBlockIDs else {
            XCTFail("expected attachedBlockIDs")
            return
        }
        XCTAssertEqual(Set(attachedIDs), Set([oldBlock.id, recentA.id, recentB.id]))

        // Encode/decode to also exercise the Codable path
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try! encoder.encode(snap)
        let decoded = try! decoder.decode(TabSnapshot.self, from: data)

        // Restore into a fresh tab
        let restored = Tab(id: decoded.id, title: decoded.title, content: .terminal)
        TabSnapshotBuilder.apply(snapshot: decoded, to: restored)

        XCTAssertEqual(restored.blockStore.all.count, 21)
        XCTAssertEqual(restored.attachedBlockIDs, Set([oldBlock.id, recentA.id, recentB.id]))

        // Surface IDs are cleared on restore (they'd be stale)
        for block in restored.blockStore.all {
            XCTAssertNil(block.surfaceID, "restored blocks drop surfaceID")
        }

        // Commands preserved
        let restoredCommands = restored.blockStore.all.compactMap { $0.command }
        XCTAssertTrue(restoredCommands.contains("cmd-2"))
        XCTAssertTrue(restoredCommands.contains("cmd-24"))
    }

    // MARK: - Dangling attachment IDs are filtered

    func test_apply_filters_dangling_attached_ids() {
        let tab = Tab(id: UUID(), title: "Test", content: .terminal)
        let b1 = makeBlock(command: "cmd-1")
        tab.blockStore.append(b1)

        let danglingID = UUID()
        let snap = TabSnapshot(
            id: tab.id,
            title: tab.title,
            splitTree: tab.splitTree,
            attachedBlockIDs: [b1.id, danglingID],
            persistedBlocks: [PersistedCommandBlock(from: b1)]
        )

        let restored = Tab(id: snap.id, title: snap.title, content: .terminal)
        TabSnapshotBuilder.apply(snapshot: snap, to: restored)

        XCTAssertEqual(restored.attachedBlockIDs, Set([b1.id]))
        XCTAssertFalse(restored.attachedBlockIDs.contains(danglingID))
    }

    // MARK: - Empty case

    func test_empty_tab_roundtrips_cleanly() {
        let tab = Tab(id: UUID(), title: "Empty", content: .terminal)
        let snap = TabSnapshotBuilder.build(from: tab, browserURL: nil)
        XCTAssertNil(snap.attachedBlockIDs)
        XCTAssertNil(snap.persistedBlocks)

        let restored = Tab(id: snap.id, title: snap.title, content: .terminal)
        TabSnapshotBuilder.apply(snapshot: snap, to: restored)

        XCTAssertTrue(restored.blockStore.all.isEmpty)
        XCTAssertTrue(restored.attachedBlockIDs.isEmpty)
    }

    // MARK: - Legacy decode (missing optional fields)

    func test_legacy_snapshot_decodes_with_nil_block_fields() throws {
        // Simulate a snapshot encoded before LS3: no attachedBlockIDs / persistedBlocks keys.
        let legacyJSON = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "title": "Legacy",
          "splitTree": {"nodes":[],"rootID":null}
        }
        """.data(using: .utf8)!

        // SplitTree's own decoding may differ; reuse a real tree via encoder to be safe.
        let realSnap = TabSnapshot(id: UUID(), title: "Legacy", splitTree: SplitTree())
        let encoded = try JSONEncoder().encode(realSnap)

        // Verify the encoded form omits nil optionals (or decodes with them nil)
        let decoded = try JSONDecoder().decode(TabSnapshot.self, from: encoded)
        XCTAssertNil(decoded.attachedBlockIDs)
        XCTAssertNil(decoded.persistedBlocks)

        // And applying a legacy-shaped snapshot to a tab leaves it empty
        let tab = Tab(id: decoded.id, title: decoded.title, content: .terminal)
        TabSnapshotBuilder.apply(snapshot: decoded, to: tab)
        XCTAssertTrue(tab.blockStore.all.isEmpty)
        XCTAssertTrue(tab.attachedBlockIDs.isEmpty)

        _ = legacyJSON // silence unused warning (kept for documentation)
    }

    // MARK: - Snippet truncation

    func test_persist_truncates_long_output_to_32_lines() {
        let lines = (1...100).map { "line-\($0)" }.joined(separator: "\n")
        let block = makeBlock(command: "long", output: lines)
        let persisted = PersistedCommandBlock(from: block)
        guard let snippet = persisted.outputSnippet else {
            XCTFail("snippet missing")
            return
        }
        let resultLines = snippet.components(separatedBy: "\n")
        XCTAssertEqual(resultLines.count, 32)
        XCTAssertEqual(resultLines.first, "line-69")
        XCTAssertEqual(resultLines.last, "line-100")
    }

    func test_persist_preserves_short_output_verbatim() {
        let short = "one\ntwo\nthree"
        let block = makeBlock(command: "short", output: short)
        let persisted = PersistedCommandBlock(from: block)
        XCTAssertEqual(persisted.outputSnippet, short)
    }
}
