import Foundation
import Testing
@testable import GujoCoreKit

@Suite("LedgerWriteAccess")
struct LedgerWriteAccessTests {
    @Test("cloudApps persist writes ledger.json")
    func cloudAppsPersists() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let ledger = Ledger(file: file, access: .cloudApps)
        try ledger.record(InstalledProduct(
            productId: 1, name: "P1", bundleSha256: "abc", installedAt: Date(), sizeBytes: 10
        ))
        #expect(Ledger(file: file).all().count == 1)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("retiredReader record throws and leaves no file")
    func retiredReaderDoesNotWrite() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-ro-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let ledger = Ledger(file: file, access: .retiredReader)
        #expect(throws: LedgerWriteDenied.retiredOwner) {
            try ledger.record(InstalledProduct(
                productId: 2, name: "P2", bundleSha256: "def", installedAt: Date(), sizeBytes: 1
            ))
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
