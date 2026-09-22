import XCTest
@testable import FreshnessKit

/// 판정은 git 없이 검증한다 — 경고가 뜨는 조건과 **안 뜨는 조건**을 둘 다 고정.
final class InstallStampFreshnessTests: XCTestCase {
    private func stamp(commit: String? = "abc123", branch: String? = "main",
                       dirty: Bool = false, root: String? = "/repo") -> InstallStampFreshness.Stamp {
        .init(commit: commit, branch: branch, dirty: dirty, sourceRoot: root)
    }

    /// 정상(머지된 main 커밋, 깨끗, 최신)이면 **조용하다**. 시끄러우면 아무도 안 읽는다.
    func testSilentWhenInstalledFromCanonicalMain() {
        XCTAssertNil(InstallStampFreshness.warning(
            tool: "t", stamp: stamp(),
            lineage: .init(mergedIntoMain: true, behindCount: 0)))
    }

    /// 몇 커밋 뒤처짐은 정상 흐름 — 임계 이하면 조용하다.
    func testSilentWhenSlightlyBehind() {
        XCTAssertNil(InstallStampFreshness.warning(
            tool: "t", stamp: stamp(),
            lineage: .init(mergedIntoMain: true, behindCount: 5)))
    }

    /// 머지 안 된 브랜치 소스 — 오늘 ADM 이 두 번 이렇게 회귀했다.
    func testWarnsWhenInstalledFromUnmergedBranch() {
        let line = InstallStampFreshness.warning(
            tool: "app-build-manager",
            stamp: stamp(branch: "fix/some-branch"),
            lineage: .init(mergedIntoMain: false, behindCount: 3))
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("fix/some-branch"), line!)
        XCTAssertTrue(line!.contains("app-build-manager"), line!)
    }

    /// 크게 뒤처진 설치본 — auditor 가 이미 고쳐진 결함을 계속 보고한 경우.
    func testWarnsWhenFarBehind() {
        let line = InstallStampFreshness.warning(
            tool: "auditor", stamp: stamp(),
            lineage: .init(mergedIntoMain: true, behindCount: 120))
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("120커밋"), line!)
    }

    /// dirty 빌드는 lineage 없이도 경고 — 소스를 재현할 수 없다.
    func testWarnsOnDirtyBuildEvenWithoutLineage() throws {
        let warning = try XCTUnwrap(InstallStampFreshness.warning(
            tool: "t", stamp: stamp(dirty: true), lineage: nil))
        // 경고가 났다는 사실만으론 "왜" 를 모른다 — 사유가 dirty 여야 한다.
        XCTAssertTrue(warning.contains("커밋 안 된 변경"), warning)
    }

    /// 스탬프가 없으면 판정 불가 — 경고가 아니라 침묵(옛 설치본·비-ADM 설치).
    func testSilentWhenNoStamp() {
        XCTAssertNil(InstallStampFreshness.warning(
            tool: "t", stamp: stamp(commit: nil, branch: nil), lineage: nil))
    }

    /// lineage 를 못 구해도(저장소 없음) dirty 가 아니면 조용하다.
    func testSilentWhenLineageUnknownAndClean() {
        XCTAssertNil(InstallStampFreshness.warning(tool: "t", stamp: stamp(), lineage: nil))
    }

    /// 경고는 stderr 로만 나가고, 끌 수 있다.
    func testReportWritesOnceAndRespectsOptOut() {
        var written: [String] = []
        let dirtyStamp = stamp(dirty: true)
        _ = InstallStampFreshness.reportToStandardError(
            tool: "t", stamp: dirtyStamp, lineage: nil, environment: [:], write: { written.append($0) })
        XCTAssertEqual(written.count, 1)

        written.removeAll()
        _ = InstallStampFreshness.reportToStandardError(
            tool: "t", stamp: dirtyStamp, lineage: nil,
            environment: ["AGENT_TOOL_FRESHNESS": "0"], write: { written.append($0) })
        XCTAssertTrue(written.isEmpty)
    }

    func testFromInfoDictionaryReadsDirtyBoolAndDirectory() {
        let stamp = InstallStampFreshness.Stamp.fromInfoDictionary([
            "SASourceCommit": "abc",
            "SASourceBranch": "main",
            "SASourceDirty": true,
            "SASourceRoot": "/repo",
            "SASourceDirectory": "/repo/apps/demo-swift",
        ])
        XCTAssertEqual(stamp.commit, "abc")
        XCTAssertEqual(stamp.branch, "main")
        XCTAssertTrue(stamp.dirty)
        XCTAssertEqual(stamp.sourceRoot, "/repo")
        XCTAssertEqual(stamp.sourceDirectory, "/repo/apps/demo-swift")
    }

    func testFromInfoPlistReadsForeignBundle() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stamp-\(UUID().uuidString).app/Contents")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plist = dir.appendingPathComponent("Info.plist")
        (["SASourceCommit": "deadbeef"] as NSDictionary).write(to: plist, atomically: true)
        let stamp = try XCTUnwrap(InstallStampFreshness.Stamp.fromInfoPlist(at: plist))
        XCTAssertEqual(stamp.commit, "deadbeef")
        XCTAssertNil(InstallStampFreshness.Stamp.fromInfoPlist(at: dir.appendingPathComponent("missing.plist")))
    }

    /// 고치는 방법을 같이 준다 — 경고만 하고 방법을 안 주면 무시된다.
    func testWarningTellsHowToFix() {
        let line = InstallStampFreshness.warning(
            tool: "t", stamp: stamp(dirty: true), lineage: nil)
        XCTAssertTrue(line!.contains("app-build-manager install"), line!)
    }
}
