// TestRunnerStore.swift
// CTerm
//
// Manages a test runner child process, parses its output in real time,
// and exposes structured results to the sidebar view and MCP tools.

import Foundation
import OSLog
import Observation

private let logger = Logger(subsystem: "com.legato3.cterm", category: "TestRunnerStore")

// MARK: - Models

enum TestStatus: String, Codable, Sendable {
    case passed, failed, running
}

struct TestCaseResult: Identifiable, Sendable {
    let id: UUID
    let name: String
    var status: TestStatus
    var duration: String?
    var output: [String]   // captured lines for this test

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.status = .running
        self.output = []
    }
}

enum RunState: Sendable {
    case idle
    case running
    case finished(exitCode: Int32)
}

// MARK: - Store

@Observable
@MainActor
final class TestRunnerStore {
    static let shared = TestRunnerStore()

    var command: String = UserDefaults.standard.string(forKey: "TestRunner.command") ?? ""
    var workDir: String = FileManager.default.currentDirectoryPath
    var state: RunState = .idle
    var results: [TestCaseResult] = []
    var rawOutput: String = ""

    var passCount: Int { results.filter { $0.status == .passed }.count }
    var failCount: Int { results.filter { $0.status == .failed }.count }
    var failures: [TestCaseResult] { results.filter { $0.status == .failed } }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    private var process: Process?
    private var parser = TestOutputParser()

    private init() {}

    // MARK: - Control

    func run(command overrideCommand: String? = nil) {
        guard !isRunning else { return }
        let cmd = overrideCommand ?? command
        guard !cmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Persist command for next launch.
        UserDefaults.standard.set(cmd, forKey: "TestRunner.command")
        self.command = cmd

        results = []
        rawOutput = ""
        parser.reset()
        state = .running

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-c", cmd]
        proc.currentDirectoryURL = URL(fileURLWithPath: workDir)
        proc.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in self?.ingest(text) }
        }

        proc.terminationHandler = { [weak self] p in
            Task { @MainActor [weak self] in
                guard let self else { return }
                pipe.fileHandleForReading.readabilityHandler = nil
                // Flush any remaining data.
                let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                if let text = String(data: remaining, encoding: .utf8), !text.isEmpty {
                    self.ingest(text)
                }
                self.state = .finished(exitCode: p.terminationStatus)
                logger.info("TestRunner finished: exit \(p.terminationStatus), \(self.passCount)P \(self.failCount)F")
                NotificationCenter.default.post(name: .testRunnerFinished, object: nil)
            }
        }

        do {
            try proc.run()
            self.process = proc
            logger.info("TestRunner started: \(cmd)")
        } catch {
            logger.error("TestRunner launch failed: \(error)")
            state = .idle
        }
    }

    func stop() {
        process?.interrupt()
        process = nil
        if case .running = state { state = .idle }
    }

    // MARK: - Output ingestion

    private func ingest(_ text: String) {
        rawOutput += text
        let lines = text.components(separatedBy: "\n")
        for line in lines where !line.isEmpty {
            if let event = parser.parse(line: line) {
                apply(event: event)
            }
        }
    }

    private func apply(event: TestOutputParser.Event) {
        switch event {
        case .started(let name):
            if !results.contains(where: { $0.name == name }) {
                results.append(TestCaseResult(name: name))
            }

        case .passed(let name, let duration):
            if let idx = results.firstIndex(where: { $0.name == name }) {
                results[idx].status = .passed
                results[idx].duration = duration
            } else {
                var r = TestCaseResult(name: name)
                r.status = .passed
                r.duration = duration
                results.append(r)
            }

        case .failed(let name, let duration):
            if let idx = results.firstIndex(where: { $0.name == name }) {
                results[idx].status = .failed
                results[idx].duration = duration
            } else {
                var r = TestCaseResult(name: name)
                r.status = .failed
                r.duration = duration
                results.append(r)
            }
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let testRunnerFinished = Notification.Name("com.legato3.cterm.testRunnerFinished")
}

// MARK: - Output parser

struct TestOutputParser {
    // XCTest: Test Case '-[Suite testName]' passed (0.001 seconds).
    private static let xcTestPassed = try! NSRegularExpression(
        pattern: #"Test Case '-\[(\S+) (\S+)\]' passed \((\S+) seconds\)"#)
    private static let xcTestFailed = try! NSRegularExpression(
        pattern: #"Test Case '-\[(\S+) (\S+)\]' failed \((\S+) seconds\)"#)

    // Swift Testing (swift test): ✔ Test testName() passed after 0.001s.
    private static let swiftTestPassed = try! NSRegularExpression(
        pattern: #"[✔✓] Test (.+?) passed"#)
    private static let swiftTestFailed = try! NSRegularExpression(
        pattern: #"[✘✗] Test (.+?) failed"#)

    // cargo test: test module::name ... ok   /  ... FAILED
    private static let cargoTest = try! NSRegularExpression(
        pattern: #"^test (.+) \.\.\. (ok|FAILED)$"#)

    // go test: --- PASS: TestName (0.00s)  /  --- FAIL: TestName (0.00s)
    private static let goTest = try! NSRegularExpression(
        pattern: #"--- (PASS|FAIL): (\S+) \((\S+)s\)"#)

    // pytest: PASSED path::test_name  /  FAILED path::test_name
    private static let pytest = try! NSRegularExpression(
        pattern: #"(PASSED|FAILED) (.+::test\S+)"#)

    // Jest: ✓ test description  /  ✕ test description  /  ● test description
    private static let jestPassed = try! NSRegularExpression(pattern: #"^\s+[✓✔] (.+)$"#)
    private static let jestFailed = try! NSRegularExpression(pattern: #"^\s+[✕✗×●] (.+)$"#)

    enum Event {
        case started(name: String)
        case passed(name: String, duration: String?)
        case failed(name: String, duration: String?)
    }

    mutating func reset() {}

    func parse(line: String) -> Event? {
        let r = NSRange(line.startIndex..., in: line)

        // XCTest passed
        if let m = Self.xcTestPassed.firstMatch(in: line, range: r) {
            let suite = capture(line, m, 1)
            let test = capture(line, m, 2)
            let dur = capture(line, m, 3)
            return .passed(name: "\(suite).\(test)", duration: dur.map { $0 + "s" })
        }
        // XCTest failed
        if let m = Self.xcTestFailed.firstMatch(in: line, range: r) {
            let suite = capture(line, m, 1)
            let test = capture(line, m, 2)
            let dur = capture(line, m, 3)
            return .failed(name: "\(suite).\(test)", duration: dur.map { $0 + "s" })
        }
        // Swift Testing passed
        if let m = Self.swiftTestPassed.firstMatch(in: line, range: r) {
            return .passed(name: capture(line, m, 1) ?? line, duration: nil)
        }
        // Swift Testing failed
        if let m = Self.swiftTestFailed.firstMatch(in: line, range: r) {
            return .failed(name: capture(line, m, 1) ?? line, duration: nil)
        }
        // cargo test
        if let m = Self.cargoTest.firstMatch(in: line, range: r) {
            let name = capture(line, m, 1) ?? line
            let verdict = capture(line, m, 2) ?? ""
            return verdict == "ok" ? .passed(name: name, duration: nil) : .failed(name: name, duration: nil)
        }
        // go test
        if let m = Self.goTest.firstMatch(in: line, range: r) {
            let verdict = capture(line, m, 1) ?? ""
            let name = capture(line, m, 2) ?? line
            let dur = capture(line, m, 3)
            return verdict == "PASS"
                ? .passed(name: name, duration: dur.map { $0 + "s" })
                : .failed(name: name, duration: dur.map { $0 + "s" })
        }
        // pytest
        if let m = Self.pytest.firstMatch(in: line, range: r) {
            let verdict = capture(line, m, 1) ?? ""
            let name = capture(line, m, 2) ?? line
            return verdict == "PASSED" ? .passed(name: name, duration: nil) : .failed(name: name, duration: nil)
        }
        // Jest passed
        if let m = Self.jestPassed.firstMatch(in: line, range: r) {
            return .passed(name: capture(line, m, 1) ?? line, duration: nil)
        }
        // Jest failed
        if let m = Self.jestFailed.firstMatch(in: line, range: r) {
            return .failed(name: capture(line, m, 1) ?? line, duration: nil)
        }

        return nil
    }

    private func capture(_ line: String, _ match: NSTextCheckingResult, _ group: Int) -> String? {
        guard group < match.numberOfRanges,
              let range = Range(match.range(at: group), in: line) else { return nil }
        return String(line[range])
    }
}
