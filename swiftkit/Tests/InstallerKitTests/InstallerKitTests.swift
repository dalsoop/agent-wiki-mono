import Foundation
import Testing
@testable import InstallerKit

@Test func emptyChecksNotInstalled() {
    let checker = InstallChecker(
        fileExists: { _ in false },
        bundleIdentifierPaths: { _ in [] },
        commandExists: { _ in false },
        brewCaskInstalled: { _ in false },
        brewFormulaInstalled: { _ in false }
    )
    let status = checker.status(for: [.executable("nope"), .brewFormula("nope")])
    #expect(!status.installed)
    #expect(status.matchedEvidence.isEmpty)
}

@Test func executableMatchReportsEvidence() {
    let checker = InstallChecker(commandExists: { $0 == "bat" })
    let status = checker.status(for: [.executable("bat"), .executable("missing")])
    #expect(status.installed)
    #expect(status.matchedEvidence.count == 1)
    #expect(status.matchedEvidence.first?.label == "Executable")
}

@Test func brewCaskRoundTrip() throws {
    let check = InstallCheck.brewCask("ripgrep")
    let data = try JSONEncoder().encode(check)
    let back = try JSONDecoder().decode(InstallCheck.self, from: data)
    #expect(back == check)
}
