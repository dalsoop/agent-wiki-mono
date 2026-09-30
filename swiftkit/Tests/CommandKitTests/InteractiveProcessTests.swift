import Foundation
import XCTest
@testable import CommandKit

final class InteractiveProcessTests: XCTestCase {
    func testCatEchoesStdinThenExitsAfterClose() throws {
        let output = LockedState(Data())
        let process = try InteractiveProcess.start("/bin/cat", [], onStdout: { chunk in
            output.withLock { $0.append(chunk) }
        })
        try process.write(Data("hello\n".utf8))
        process.closeStdin()
        XCTAssertEqual(process.waitUntilExit(timeout: 5), 0)
        XCTAssertEqual(output.withLock { String(decoding: $0, as: UTF8.self) }, "hello\n")
    }

    func testStderrIsSeparateByDefault() throws {
        let out = LockedState(Data())
        let err = LockedState(Data())
        let process = try InteractiveProcess.start(
            "/bin/sh", ["-c", "echo out; echo err 1>&2"],
            onStdout: { chunk in out.withLock { $0.append(chunk) } },
            onStderr: { chunk in err.withLock { $0.append(chunk) } })
        XCTAssertEqual(process.waitUntilExit(timeout: 5), 0)
        XCTAssertEqual(out.withLock { String(decoding: $0, as: UTF8.self) }, "out\n")
        XCTAssertEqual(err.withLock { String(decoding: $0, as: UTF8.self) }, "err\n")
    }

    func testMergedStderrArrivesOnStdout() throws {
        let out = LockedState(Data())
        let options = InteractiveProcessOptions(mergeStderrIntoStdout: true)
        let process = try InteractiveProcess.start(
            "/bin/sh", ["-c", "echo out; echo err 1>&2"], options: options,
            onStdout: { chunk in out.withLock { $0.append(chunk) } })
        XCTAssertEqual(process.waitUntilExit(timeout: 5), 0)
        let text = out.withLock { String(decoding: $0, as: UTF8.self) }
        XCTAssertTrue(text.contains("out"))
        XCTAssertTrue(text.contains("err"))
    }

    func testTerminateEscalatesToKill() throws {
        // Wait until the trap is installed; a TERM sent before it would end the shell at once
        // and never exercise the escalation. The ignored TERM is inherited by `sleep`.
        let ready = LockedState(false)
        let process = try InteractiveProcess.start(
            "/bin/sh", ["-c", "trap '' TERM; echo ready; sleep 30"],
            options: InteractiveProcessOptions(newProcessGroup: true),
            onStdout: { _ in ready.withLock { $0 = true } })
        let deadline = Date().addingTimeInterval(5)
        while !ready.withLock({ $0 }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(ready.withLock { $0 })
        let started = Date()
        process.terminate(grace: 0.5)
        XCTAssertNotNil(process.waitUntilExit(timeout: 5))
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.4, "TERM is ignored, so KILL comes after the grace")
        XCTAssertFalse(process.isRunning)
    }

    func testProcessGroupTerminateKillsGrandchild() throws {
        let lines = LineAccumulator()
        let grandchild = LockedState<Int32?>(nil)
        let options = InteractiveProcessOptions(newProcessGroup: true)
        let process = try InteractiveProcess.start(
            "/bin/sh", ["-c", "sleep 0.3; sleep 30 & echo $!; wait"], options: options,
            onStdout: { chunk in
                for line in lines.append(chunk) {
                    grandchild.withLock { $0 = Int32(line.trimmingCharacters(in: .whitespaces)) }
                }
            })
        let deadline = Date().addingTimeInterval(5)
        while grandchild.withLock({ $0 }) == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let pid = try XCTUnwrap(grandchild.withLock { $0 })
        process.terminate(grace: 1)
        XCTAssertNotNil(process.waitUntilExit(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertNotEqual(kill(pid, 0), 0, "grandchild should be gone")
    }

    func testWriteAfterExitThrowsInsteadOfCrashing() throws {
        let process = try InteractiveProcess.start("/usr/bin/true", [], onStdout: { _ in })
        XCTAssertEqual(process.waitUntilExit(timeout: 5), 0)
        XCTAssertThrowsError(try process.write(Data(repeating: 0x41, count: 200_000)))
    }

    func testWriteAfterCloseThrowsStdinClosed() throws {
        let process = try InteractiveProcess.start("/bin/cat", [], onStdout: { _ in })
        process.closeStdin()
        XCTAssertThrowsError(try process.write(Data("x".utf8))) { error in
            XCTAssertEqual(error as? InteractiveProcessError, .stdinClosed)
        }
        _ = process.waitUntilExit(timeout: 5)
    }

    func testLargeOutputIsStreamedCompletely() throws {
        let count = LockedState(0)
        let process = try InteractiveProcess.start(
            "/bin/sh", ["-c", "head -c 5000000 /dev/zero"],
            onStdout: { chunk in count.withLock { $0 += chunk.count } })
        XCTAssertEqual(process.waitUntilExit(timeout: 20), 0)
        XCTAssertEqual(count.withLock { $0 }, 5_000_000)
    }

    func testLineAccumulatorSplitsAndFlushes() {
        let lines = LineAccumulator()
        XCTAssertEqual(lines.append(Data("a\nb".utf8)), ["a"])
        XCTAssertEqual(lines.append(Data("c\nd".utf8)), ["bc"])
        XCTAssertEqual(lines.flush(), "d")
        XCTAssertNil(lines.flush())
    }

    func testLineAccumulatorDropsOversizedUnfinishedLine() {
        let lines = LineAccumulator(limit: 4)
        XCTAssertEqual(lines.append(Data("123456".utf8)), [])
        XCTAssertNil(lines.flush())
    }
}
