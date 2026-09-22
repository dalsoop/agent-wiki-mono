import Foundation
import XCTest
@testable import DoctorContract

final class DomainDoctorProvidersTests: XCTestCase {
    private struct Sample: Codable, Equatable {
        var name: String
    }

    func testMissingJSONFileIsClean() async {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).json")
        let findings = await CodableJSONFileDoctorProvider(
            id: "json",
            url: url,
            as: Sample.self,
            subject: "t",
            fileExists: { _ in false }
        ).run()
        XCTAssertTrue(findings.isEmpty)
    }

    func testCorruptJSONFileFails() async {
        let url = URL(fileURLWithPath: "/tmp/corrupt.json")
        let findings = await CodableJSONFileDoctorProvider(
            id: "json",
            url: url,
            as: Sample.self,
            subject: "t",
            fileExists: { _ in true },
            read: { _ in Data("{".utf8) }
        ).run()
        XCTAssertEqual(findings.first?.severity, .fail)
        XCTAssertEqual(findings.first?.source, "json")
    }

    func testValidJSONFileIsClean() async throws {
        let url = URL(fileURLWithPath: "/tmp/ok.json")
        let data = try JSONEncoder().encode(Sample(name: "ok"))
        let findings = await CodableJSONFileDoctorProvider(
            id: "json",
            url: url,
            as: Sample.self,
            subject: "t",
            fileExists: { _ in true },
            read: { _ in data }
        ).run()
        XCTAssertTrue(findings.isEmpty)
    }

    func testUninstalledLaunchAgentIsClean() async {
        let findings = await LaunchAgentLoadedIfInstalledProvider(
            id: "la",
            label: "net.example.x",
            inspect: { (false, false) }
        ).run()
        XCTAssertTrue(findings.isEmpty)
    }

    func testInstalledUnloadedLaunchAgentFails() async {
        let findings = await LaunchAgentLoadedIfInstalledProvider(
            id: "la",
            label: "net.example.x",
            inspect: { (true, false) }
        ).run()
        XCTAssertEqual(findings.first?.severity, .fail)
    }

    func testMissingApplicationBundleFails() async {
        let findings = await InstalledApplicationBundleProvider(
            id: "apps",
            appNames: ["Dub 00 Studio"],
            applicationsDirectory: "/Applications",
            fileExists: { _ in false }
        ).run()
        XCTAssertEqual(findings.count, 1)
        XCTAssertTrue(findings[0].detail.contains("Dub 00 Studio.app"))
    }

    func testUnimplementedDomainDoctorFailsClosed() async {
        let findings = await UnimplementedDomainDoctorProvider(subject: "demo").run()
        XCTAssertEqual(findings.first?.severity, .fail)
        XCTAssertEqual(findings.first?.source, "domain-unimplemented")
    }
}
