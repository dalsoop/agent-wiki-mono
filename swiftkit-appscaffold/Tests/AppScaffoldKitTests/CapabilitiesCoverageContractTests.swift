import Foundation
import Testing
@testable import AppScaffoldKit

/// CLI Capabilities Envelope 규격 검증 상위 공용 테스트.
@Suite struct CapabilitiesCoverageContractTests {
    @Test func validCapabilitiesEnvelopePasses() {
        let sample = """
        {
          "commands": {
            "capabilities": { "description": "Capabilities" },
            "status": { "description": "Status" }
          },
          "schema": "interop/v1"
        }
        """
        #expect(CapabilitiesCoverageContract.verifyCapabilitiesJSONString(sample))
    }

    @Test func emptyOrMalformedEnvelopeFails() {
        #expect(!CapabilitiesCoverageContract.verifyCapabilitiesJSONString("{}"))
        #expect(!CapabilitiesCoverageContract.verifyCapabilitiesJSONString("not-json"))
        #expect(!CapabilitiesCoverageContract.verifyCapabilitiesJSONString("{\"commands\": {}}"))
    }
}
