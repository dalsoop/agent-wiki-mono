import Testing
@testable import InstallHealthKit

@Suite("PATH CLI 심링크·Sparkle rpath 검사")
struct CLIInstallAuditTests {
    private let audit = CLIInstallAudit()

    @Test("심링크이고 타겟이 있으면 깨끗")
    func healthySymlink() {
        let spec = CLIInstallSpec(
            name: "app-health-guard",
            path: "/opt/homebrew/bin/app-health-guard",
            isSymbolicLink: true,
            destinationExists: true
        )
        #expect(audit.auditSymlink(spec).isEmpty)
        #expect(audit.auditOne(spec).isEmpty)
    }

    @Test("복사본이면 경고")
    func copyIsWarning() {
        let spec = CLIInstallSpec(
            name: "app-health-guard",
            path: "/opt/homebrew/bin/app-health-guard",
            isSymbolicLink: false
        )
        let issues = audit.auditSymlink(spec)
        #expect(issues.count == 1)
        #expect(issues[0].kind == .cliSymlinkCheck)
        #expect(issues[0].severity == .warning)
        #expect(issues[0].subject == "app-health-guard")
        #expect(issues[0].detail == "CLI가 복사본입니다 — 심링크로 전환하세요")
        #expect(!issues[0].isAutoFixable)
    }

    @Test("dangling 심링크면 오류")
    func danglingSymlinkIsError() {
        let spec = CLIInstallSpec(
            name: "ghost-cli",
            path: "/opt/homebrew/bin/ghost-cli",
            isSymbolicLink: true,
            destinationExists: false
        )
        let issues = audit.auditSymlink(spec)
        #expect(issues.count == 1)
        #expect(issues[0].kind == .cliSymlinkCheck)
        #expect(issues[0].severity == .error)
        #expect(issues[0].detail == "dangling 심링크")
    }

    @Test("otool -L 에 Sparkle 이 있으면 경고")
    func sparkleLinkIsWarning() {
        let otool = """
        /opt/homebrew/bin/foo:
        \t/usr/lib/libobjc.A.dylib (compatibility version 1.0.0)
        \t@rpath/Sparkle.framework/Versions/B/Sparkle (compatibility version 1.6.0)
        """
        let spec = CLIInstallSpec(
            name: "foo",
            path: "/opt/homebrew/bin/foo",
            isSymbolicLink: true,
            destinationExists: true,
            otoolL: otool
        )
        let issues = audit.auditSparkleRpath(spec)
        #expect(issues.count == 1)
        #expect(issues[0].kind == .cliSparkleRpath)
        #expect(issues[0].severity == .warning)
        #expect(issues[0].subject == "foo")
    }

    @Test("Sparkle 없으면 깨끗")
    func noSparkleIsClean() {
        let spec = CLIInstallSpec(
            name: "foo",
            path: "/opt/homebrew/bin/foo",
            isSymbolicLink: true,
            destinationExists: true,
            otoolL: "\t/usr/lib/libobjc.A.dylib (compatibility version 1.0.0)\n"
        )
        #expect(audit.auditSparkleRpath(spec).isEmpty)
    }

    @Test("복사본이면서 Sparkle 이면 두 규칙 모두")
    func bothRulesFire() {
        let spec = CLIInstallSpec(
            name: "foo",
            path: "/opt/homebrew/bin/foo",
            isSymbolicLink: false,
            otoolL: "\t@rpath/Sparkle.framework/Versions/B/Sparkle\n"
        )
        let issues = audit.auditOne(spec)
        #expect(Set(issues.map(\.kind)) == [.cliSymlinkCheck, .cliSparkleRpath])
    }

    @Test("여러 CLI 는 subject 순")
    func sortedBySubject() {
        let specs = [
            CLIInstallSpec(name: "zeta", path: "/opt/homebrew/bin/zeta", isSymbolicLink: false),
            CLIInstallSpec(name: "alpha", path: "/opt/homebrew/bin/alpha", isSymbolicLink: false),
        ]
        #expect(audit.audit(specs).map(\.subject) == ["alpha", "zeta"])
    }
}
