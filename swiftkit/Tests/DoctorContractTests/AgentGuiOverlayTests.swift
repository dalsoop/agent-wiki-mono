import Testing
import DoctorContract

@Suite("AgentGuiOverlay")
struct AgentGuiOverlayTests {
    @Test("좌석 IDE는 nil, Orca·Computer Use만 가족")
    func seatsAreNilOverlayCounts() {
        #expect(AgentGuiOverlay.classify("Cursor Helper (Renderer)") == nil)
        #expect(AgentGuiOverlay.classify("Claude Helper") == nil)
        #expect(AgentGuiOverlay.classify("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome") == nil)
        #expect(AgentGuiOverlay.classify("Electron Helper") == nil)
        #expect(AgentGuiOverlay.classify("/Applications/Orca.app/Contents/MacOS/Orca Helper") == "Orca")
        #expect(AgentGuiOverlay.classify("SkyComputerUseService") == "SkyComputer")
        #expect(AgentGuiOverlay.classify("SkyComputerUseClient") == "SkyComputer")
    }

    @Test("가족 상한 — Orca 헬퍼 11개는 10")
    func familyCapDoesNotLetOrcaAloneHitSeatEra50() {
        let orca = (0..<11).map { _ in "/Applications/Orca.app/Contents/MacOS/Orca Helper" }
        let (total, by) = AgentGuiOverlay.weight(commands: orca)
        #expect(by["Orca"] == 10)
        #expect(total == 10)
        #expect(total <= AgentGuiOverlay.defaultSoftCap)
    }

    @Test("Orca 풀 + Computer Use 몇 개는 캡을 넘긴다")
    func orcaPlusComputerUseTripsOverlayCap() {
        var cmds = (0..<11).map { _ in "/Applications/Orca.app/Contents/Frameworks/Orca Helper" }
        cmds.append("SkyComputerUseClient")
        cmds.append("SkyComputerUseService")
        cmds.append("SkyComputerUseClient")
        let (total, _) = AgentGuiOverlay.weight(commands: cmds)
        #expect(total == 13)
        #expect(total > AgentGuiOverlay.defaultSoftCap)
    }

    @Test("죽은 캡(좌석 시대 기본·이론 상한 초과)은 오버레이 기본으로 올린다")
    func deadCapsBecomeUsable() {
        #expect(AgentGuiOverlay.theoreticalMaxWeight == 22)
        #expect(AgentGuiOverlay.defaultSoftCap < AgentGuiOverlay.theoreticalMaxWeight)
        #expect(AgentGuiOverlay.usableCap(50) == 12)
        #expect(AgentGuiOverlay.usableCap(25) == 12)
        #expect(AgentGuiOverlay.usableCap(40) == 12)
        #expect(AgentGuiOverlay.usableCap(8) == 8)
        #expect(AgentGuiOverlay.usableCap(20) == 20)
        #expect(!AgentGuiOverlay.isDeadCap(AgentGuiOverlay.defaultSoftCap))
    }
}
