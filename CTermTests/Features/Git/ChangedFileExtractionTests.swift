import XCTest
@testable import CTerm

/// Pure-parsing tests for `ChangedFileExtractor`. These don't shell out to
/// git — they feed canned `numstat` / `porcelain` strings into the parsers
/// and verify the merged `[ChangedFile]` matches expectations.
@MainActor
final class ChangedFileExtractionTests: XCTestCase {

    // MARK: - numstat parsing

    func test_numstat_plainFiles() {
        let raw = """
        12\t4\tSources/App/Foo.swift
        0\t0\tREADME.md
        7\t3\tdir with space/bar.txt
        """
        let entries = ChangedFileExtractor.parseNumstat(raw)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].additions, 12)
        XCTAssertEqual(entries[0].deletions, 4)
        XCTAssertEqual(entries[0].path, "Sources/App/Foo.swift")
        XCTAssertNil(entries[0].oldPath)
        XCTAssertEqual(entries[2].path, "dir with space/bar.txt")
    }

    func test_numstat_binaryFilesTreatedAsZeroCounts() {
        let raw = "-\t-\tLogo.png\n"
        let entries = ChangedFileExtractor.parseNumstat(raw)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].additions, 0)
        XCTAssertEqual(entries[0].deletions, 0)
        XCTAssertEqual(entries[0].path, "Logo.png")
    }

    func test_numstat_simpleRename() {
        let raw = "1\t1\told.swift => new.swift\n"
        let entries = ChangedFileExtractor.parseNumstat(raw)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].path, "new.swift")
        XCTAssertEqual(entries[0].oldPath, "old.swift")
    }

    func test_numstat_braceRename() {
        let raw = "2\t2\tSources/{Old => New}/File.swift\n"
        let entries = ChangedFileExtractor.parseNumstat(raw)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].path, "Sources/New/File.swift")
        XCTAssertEqual(entries[0].oldPath, "Sources/Old/File.swift")
    }

    func test_numstat_empty() {
        XCTAssertTrue(ChangedFileExtractor.parseNumstat("").isEmpty)
    }

    // MARK: - porcelain parsing

    func test_porcelain_variousStatuses() {
        let raw = """
         M Sources/App/Foo.swift
        A  Sources/App/NewThing.swift
         D deleted.swift
        ?? untracked.txt
        """
        let entries = ChangedFileExtractor.parsePorcelain(raw)
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[0].status, .modified)
        XCTAssertEqual(entries[0].path, "Sources/App/Foo.swift")
        XCTAssertEqual(entries[1].status, .added)
        XCTAssertEqual(entries[1].path, "Sources/App/NewThing.swift")
        XCTAssertEqual(entries[2].status, .deleted)
        XCTAssertEqual(entries[2].path, "deleted.swift")
        XCTAssertEqual(entries[3].status, .untracked)
        XCTAssertEqual(entries[3].path, "untracked.txt")
        XCTAssertNil(entries[3].oldPath)
    }

    func test_porcelain_rename() {
        let raw = "R  old/path.swift -> new/path.swift\n"
        let entries = ChangedFileExtractor.parsePorcelain(raw)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].status, .renamed)
        XCTAssertEqual(entries[0].path, "new/path.swift")
        XCTAssertEqual(entries[0].oldPath, "old/path.swift")
    }

    func test_porcelain_empty() {
        XCTAssertTrue(ChangedFileExtractor.parsePorcelain("").isEmpty)
    }

    // MARK: - merge

    func test_merge_numstatSuppliesCounts_porcelainSuppliesStatus() {
        let numstat = ChangedFileExtractor.parseNumstat("5\t2\tFoo.swift\n0\t3\tBar.swift\n")
        let porcelain = ChangedFileExtractor.parsePorcelain(" M Foo.swift\n D Bar.swift\n")
        let merged = ChangedFileExtractor.merge(numstats: numstat, porcelain: porcelain, workDir: "/tmp")

        XCTAssertEqual(merged.count, 2)
        let byPath = Dictionary(uniqueKeysWithValues: merged.map { ($0.path, $0) })
        XCTAssertEqual(byPath["Foo.swift"]?.status, .modified)
        XCTAssertEqual(byPath["Foo.swift"]?.additions, 5)
        XCTAssertEqual(byPath["Foo.swift"]?.deletions, 2)
        XCTAssertEqual(byPath["Bar.swift"]?.status, .deleted)
        XCTAssertEqual(byPath["Bar.swift"]?.deletions, 3)
    }

    func test_merge_untrackedFromPorcelainOnly() throws {
        // Create an untracked file so merge can line-count it.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let filePath = "untracked.txt"
        try "line1\nline2\nline3\n".write(
            to: tmp.appendingPathComponent(filePath), atomically: true, encoding: .utf8
        )

        let porcelain = ChangedFileExtractor.parsePorcelain("?? \(filePath)\n")
        let merged = ChangedFileExtractor.merge(numstats: [], porcelain: porcelain, workDir: tmp.path)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].status, .untracked)
        XCTAssertEqual(merged[0].path, filePath)
        XCTAssertEqual(merged[0].additions, 3)
        XCTAssertEqual(merged[0].deletions, 0)

        try? FileManager.default.removeItem(at: tmp)
    }

    func test_merge_renameStatusPreserved() {
        // Rename appears in both numstat (with counts) and porcelain (with
        // old/new paths). Merged entry should carry rename status + oldPath.
        let numstat = ChangedFileExtractor.parseNumstat("1\t1\told.swift => new.swift\n")
        let porcelain = ChangedFileExtractor.parsePorcelain("R  old.swift -> new.swift\n")
        let merged = ChangedFileExtractor.merge(numstats: numstat, porcelain: porcelain, workDir: "/tmp")

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].status, .renamed)
        XCTAssertEqual(merged[0].path, "new.swift")
        XCTAssertEqual(merged[0].oldPath, "old.swift")
    }

    // MARK: - expandRenamePath

    func test_expandRenamePath_plain() {
        XCTAssertNil(ChangedFileExtractor.expandRenamePath("plain/path.swift"))
    }

    func test_expandRenamePath_simpleArrow() {
        let expanded = ChangedFileExtractor.expandRenamePath("a.swift => b.swift")
        XCTAssertEqual(expanded?.0, "a.swift")
        XCTAssertEqual(expanded?.1, "b.swift")
    }

    func test_expandRenamePath_braceForm() {
        let expanded = ChangedFileExtractor.expandRenamePath("src/{x => y}/file.swift")
        XCTAssertEqual(expanded?.0, "src/x/file.swift")
        XCTAssertEqual(expanded?.1, "src/y/file.swift")
    }
}
