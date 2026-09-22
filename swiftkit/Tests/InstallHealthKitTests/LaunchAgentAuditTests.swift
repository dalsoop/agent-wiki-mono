import Testing
@testable import InstallHealthKit

private struct StubPaths: PathExisting {
    var existing: Set<String> = []
    func exists(_ path: String) -> Bool { existing.contains(path) }
}

private let bundle = "/Applications/Foo.app"
private let exe = "/Applications/Foo.app/Contents/MacOS/Foo"

@Suite struct LaunchAgentAuditTests {
    private func audit(existing: Set<String> = [bundle]) -> LaunchAgentAudit {
        LaunchAgentAudit(paths: StubPaths(existing: existing))
    }

    @Test func flagsDirectExec() {
        let spec = LaunchAgentSpec(label: "net.ranode.foo", programArguments: [exe], isPeriodic: false)
        let kinds = audit().audit(spec).map(\.kind)
        #expect(kinds == [.launchAgentDirectExec])
    }

    @Test func acceptsOpenForm() {
        let spec = LaunchAgentSpec(label: "net.ranode.foo",
                                   programArguments: ["/usr/bin/open", "-a", bundle],
                                   isPeriodic: false)
        #expect(audit().audit(spec).isEmpty)
    }

    /// 주기잡(--tick)의 직접 exec 는 정상 — open -a 로 바꾸면 매 주기 GUI 가 앞으로 튀어나온다.
    @Test func periodicDirectExecIsAllowed() {
        let spec = LaunchAgentSpec(label: "net.ranode.scheduler",
                                   programArguments: [exe, "--tick"],
                                   isPeriodic: true)
        #expect(audit().audit(spec).isEmpty)
        #expect(LaunchAgentAudit.repairedProgramArguments(for: spec) == nil)
    }

    @Test func flagsDangling() {
        let spec = LaunchAgentSpec(label: "net.ranode.foo",
                                   programArguments: ["/usr/bin/open", "-a", bundle],
                                   isPeriodic: false)
        let kinds = audit(existing: []).audit(spec).map(\.kind)
        #expect(kinds == [.launchAgentDangling])
    }

    @Test func repairsDirectExecToOpen() {
        let spec = LaunchAgentSpec(label: "net.ranode.foo", programArguments: [exe], isPeriodic: false)
        #expect(LaunchAgentAudit.repairedProgramArguments(for: spec) == ["/usr/bin/open", "-a", bundle])
    }

    @Test func parsesPlistIncludingProgramAndPeriodicKeys() {
        let a = LaunchAgentSpec(label: "l", plist: ["Program": exe, "StartInterval": 60])
        #expect(a.programArguments == [exe])
        #expect(a.isPeriodic)
        #expect(a.isDirectExec)
        #expect(a.referencedBundlePath == bundle)

        let b = LaunchAgentSpec(label: "l", plist: ["ProgramArguments": ["/usr/bin/open", "-a", bundle]])
        #expect(!b.isDirectExec)
        #expect(!b.isPeriodic)
        #expect(b.referencedBundlePath == bundle)
    }

    @Test func calendarIntervalAlsoCountsAsPeriodic() {
        let spec = LaunchAgentSpec(label: "l", plist: [
            "ProgramArguments": [exe, "--tick"],
            "StartCalendarInterval": ["Hour": 3],
        ])
        #expect(spec.isPeriodic)
        #expect(audit().audit(spec).isEmpty)
    }
}
