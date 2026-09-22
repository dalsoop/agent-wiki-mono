import Testing
import Foundation
@testable import MachineIdentityKit

@Suite("MachineIdentityKit Tests")
struct MachineIdentityKitTests {

    @Test("MachineIdentity computes storageFolderKey correctly")
    func testStorageFolderKeyGeneration() {
        let identity = MachineIdentity(
            hardwareUUID: "6D756EEF-1234-5678-ABCD-000000000000",
            serialNumber: "C02G1234MD6R",
            hostName: "jeonghanui-macbookpro.local",
            modelIdentifier: "MacBookPro18,1",
            architecture: "arm64",
            operatorUser: "jeonghan"
        )

        #expect(identity.storageFolderKey == "jeonghanui-macbookpro-6d756eef")
        #expect(identity.id == "6D756EEF-1234-5678-ABCD-000000000000")
    }

    @Test("MachineIdentity respects custom storageFolderKey override")
    func testStorageFolderKeyOverride() {
        let identity = MachineIdentity(
            hardwareUUID: "6D756EEF-1234-5678-ABCD-000000000000",
            serialNumber: "C02G1234MD6R",
            hostName: "jeonghanui-macbookpro.local",
            modelIdentifier: "MacBookPro18,1",
            architecture: "arm64",
            operatorUser: "jeonghan",
            storageFolderKey: "custom-node-01"
        )

        #expect(identity.storageFolderKey == "custom-node-01")
    }

    @Test("OriginMachineDetector extracts local machine identity")
    func testDetectorExecution() async {
        let detector = OriginMachineDetector()
        let origin = await detector.detectCurrentMachine()

        #expect(!origin.hostName.isEmpty)
        #expect(!origin.architecture.isEmpty)

        let identity = await detector.detectMachineIdentity()
        #expect(!identity.hostName.isEmpty)
        #expect(!identity.storageFolderKey.isEmpty)
    }
}
