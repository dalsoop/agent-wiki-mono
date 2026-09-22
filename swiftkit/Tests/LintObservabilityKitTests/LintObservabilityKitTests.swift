import Foundation
import os
import LintObservabilityKit
import Testing

final class TestOutputBuffer: Sendable {
    private struct State: Sendable {
        var lines: [String] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func append(_ str: String) {
        state.withLock { s in
            s.lines.append(str)
        }
    }

    var joined: String {
        state.withLock { s in
            s.lines.joined()
        }
    }

    func contains(_ substring: String) -> Bool {
        state.withLock { s in
            s.lines.contains(where: { $0.contains(substring) })
        }
    }
}

@Suite("LintObservabilityKit Tests")
struct LintObservabilityKitTests {

    @Test("TUI Engine renders ANSI frames in TTY mode")
    func testTUIEngineTTYRendering() {
        let buffer = TestOutputBuffer()
        let sink: LintTUIEngine.OutputSink = { str in
            buffer.append(str)
        }

        let engine = LintTUIEngine(isTTY: true, sink: sink)
        engine.start(totalFiles: 100, totalApps: 10, workerCount: 4)

        // Cursor should be hidden initially
        #expect(buffer.contains("\u{001B}[?25l"))

        engine.updateWorker(lane: 0, app: "apps/agent-cli-scaffold", rule: "PackageManifestStaticRule", elapsedMs: 350)
        engine.updateWorker(lane: 1, app: "apps/gujo-cloud-apps", rule: "ForkRule", elapsedMs: 600, isSubprocess: true)
        engine.advanceFile(count: 25)
        engine.advanceApp(count: 2)
        engine.recordViolation(app: "apps/my-app", rule: "NoConstantBindingRule", message: "unused binding", isP0: true)

        engine.renderFrame()

        let joined = buffer.joined
        #expect(joined.contains("[LINT RUN]"))
        #expect(joined.contains("25/100 Files") || joined.contains("2/10 Apps"))
        #expect(joined.contains("W1:"))
        #expect(joined.contains("W2:"))
        #expect(joined.contains("Fork"))
        #expect(joined.contains("NoConstantBindingRule"))
        #expect(joined.contains("[P0]"))

        engine.stop()

        // Cursor should be restored
        #expect(buffer.contains("\u{001B}[?25h"))
        #expect(buffer.contains("[LINT COMPLETED]"))
    }

    @Test("TUI Engine falls back gracefully in Non-TTY mode without ANSI codes")
    func testTUIEngineNonTTYFallback() {
        let buffer = TestOutputBuffer()
        let sink: LintTUIEngine.OutputSink = { str in
            buffer.append(str)
        }

        let engine = LintTUIEngine(isTTY: false, sink: sink)
        engine.start(totalFiles: 100, totalApps: 5)

        engine.advanceFile(count: 50)
        engine.recordViolation(app: "apps/bad-app", rule: "NoForceUnwrap", message: "found !", isP0: false)
        engine.advanceFile(count: 50)
        engine.stop()

        let joined = buffer.joined
        // No ANSI escape character in Non-TTY mode
        #expect(!joined.contains("\u{001B}"))
        #expect(joined.contains("[LINT] Scan started: 100 files"))
        #expect(joined.contains("[LINT] 50/100 files (50.0%)") || joined.contains("100/100 files (100.0%)"))
        #expect(joined.contains("[WARN] apps/bad-app - NoForceUnwrap: found !"))
        #expect(joined.contains("[LINT COMPLETED] Scanned 100 files"))
    }

    @Test("Chrome Trace Exporter generates valid Perfetto-compatible JSON")
    func testChromeTraceExporterFormat() throws {
        let events: [ChromeTraceExporter.TraceEvent] = [
            .processMetadata(name: "AgentLintCatalog Runner", pid: 1),
            .threadMetadata(name: "Worker-0 (Core 0)", pid: 1, tid: 1),
            .complete(
                name: "Scan: apps/detailpage-template-studio",
                cat: "lint.app",
                tsMicroseconds: 1_726_550_000_100_000,
                durMicroseconds: 45_000,
                pid: 1,
                tid: 1,
                args: ["appSlug": "detailpage-template-studio", "filesCount": "28"]
            ),
            .complete(
                name: "FormatArgSpecifierRule",
                cat: "lint.rule",
                tsMicroseconds: 1_726_550_000_110_000,
                durMicroseconds: 3_200,
                pid: 1,
                tid: 1,
                args: ["ruleId": "FormatArgSpecifierRule", "violations": "0"]
            ),
            .instant(
                name: "Checkpoint",
                cat: "lint.marker",
                tsMicroseconds: 1_726_550_000_150_000,
                pid: 1,
                tid: 1
            )
        ]

        let jsonData = try ChromeTraceExporter.exportData(events: events)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        #expect(jsonObject != nil)
        #expect(jsonObject?["displayTimeUnit"] as? String == "ms")

        let rawEvents = jsonObject?["traceEvents"] as? [[String: Any]]
        #expect(rawEvents?.count == 5)

        // Verify Process metadata
        let procEvent = rawEvents?.first(where: { ($0["name"] as? String) == "process_name" })
        #expect(procEvent?["ph"] as? String == "M")

        // Verify Complete event
        let completeEvent = rawEvents?.first(where: { ($0["name"] as? String) == "FormatArgSpecifierRule" })
        #expect(completeEvent?["ph"] as? String == "X")
        #expect(completeEvent?["dur"] as? Int == 3200)
        #expect((completeEvent?["args"] as? [String: Any])?["ruleId"] as? String == "FormatArgSpecifierRule")
    }

    @Test("Chrome Trace Session concurrent recording and file export")
    func testChromeTraceSessionConcurrent() throws {
        let session = ChromeTraceSession(processName: "TestRunner", threadCount: 4)

        DispatchQueue.concurrentPerform(iterations: 50) { i in
            session.recordComplete(
                name: "Rule-\(i)",
                cat: "lint.rule",
                startRelativeMicros: Int64(i * 1000),
                durationMicros: 500,
                pid: 1,
                tid: (i % 4) + 1,
                args: ["index": "\(i)"]
            )
        }

        let all = session.allEvents()
        // 1 process metadata + 4 thread metadata + 50 complete events = 55 events
        #expect(all.count == 55)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-trace-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try session.export(to: tempURL)
        #expect(FileManager.default.fileExists(atPath: tempURL.path))

        let fileData = try Data(contentsOf: tempURL)
        #expect(!fileData.isEmpty)
    }
}
