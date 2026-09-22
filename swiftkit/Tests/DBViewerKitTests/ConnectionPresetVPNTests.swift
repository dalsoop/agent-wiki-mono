import Foundation
import XCTest
@testable import DBViewerKit
import VPNKit

final class ConnectionPresetVPNTests: XCTestCase {
    func testLegacyRequiredTunnelMigratesWhenNewKeyIsAbsent() throws {
        let preset = try decode(
            """
            {"id":"p","name":"p","jumpHost":"root@jump",
             "kubeHost":"root@10.0.50.100","namespaceFilter":"",
             "defaultDatabase":"","queryTimeoutSeconds":30,
             "defaultLimit":100,"requiredTunnel":"office"}
            """
        )

        XCTAssertEqual(preset.recoveryPreferredVPN, .legacy("office"))
    }

    func testExplicitNullRecoveryPreferenceOverridesLegacyFallback() throws {
        let preset = try decode(
            """
            {"id":"p","name":"p","jumpHost":"root@jump",
             "kubeHost":"root@10.0.50.100","namespaceFilter":"",
             "defaultDatabase":"","queryTimeoutSeconds":30,
             "defaultLimit":100,"requiredTunnel":"office",
             "recovery_preferred_vpn":null}
            """
        )

        XCTAssertNil(preset.recoveryPreferredVPN)
    }

    func testNewRecoveryPreferenceWinsOverLegacyValue() throws {
        let preset = try decode(
            """
            {"id":"p","name":"p","jumpHost":"root@jump",
             "kubeHost":"root@10.0.50.100","namespaceFilter":"",
             "defaultDatabase":"","queryTimeoutSeconds":30,
             "defaultLimit":100,"requiredTunnel":"old",
             "recovery_preferred_vpn":{"serviceID":"service-uuid",
               "displayName":"Office VPN","legacyIdentifier":null}}
            """
        )

        XCTAssertEqual(
            preset.recoveryPreferredVPN,
            VPNServiceReference(
                serviceID: "service-uuid",
                displayName: "Office VPN"
            )
        )
    }

    func testDeployedCamelCaseRecoveryPreferenceStillDecodes() throws {
        let preset = try decode(
            """
            {"id":"p","name":"p","jumpHost":"root@jump",
             "kubeHost":"root@10.0.50.100","namespaceFilter":"",
             "defaultDatabase":"","queryTimeoutSeconds":30,
             "defaultLimit":100,"requiredTunnel":"old",
             "recoveryPreferredVPN":{"serviceID":"service-uuid",
               "displayName":"Deployed VPN","legacyIdentifier":null}}
            """
        )

        XCTAssertEqual(
            preset.recoveryPreferredVPN,
            VPNServiceReference(
                serviceID: "service-uuid",
                displayName: "Deployed VPN"
            )
        )
    }

    func testEncodingDualWritesNewAndLegacyKeys() throws {
        let preset = ConnectionPreset(
            recoveryPreferredVPN: VPNServiceReference(
                serviceID: "service-uuid",
                displayName: "Office VPN"
            )
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(preset)
            ) as? [String: Any]
        )

        XCTAssertNotNil(object["recovery_preferred_vpn"])
        XCTAssertNil(object["recoveryPreferredVPN"])
        XCTAssertEqual(object["requiredTunnel"] as? String, "Office VPN")
    }

    func testEncodingExplicitNullDualWritesBothKeys() throws {
        let preset = ConnectionPreset(
            requiredTunnel: "legacy",
            recoveryPreferredVPN: nil
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(preset)
            ) as? [String: Any]
        )

        XCTAssertTrue(object["recovery_preferred_vpn"] is NSNull)
        XCTAssertNil(object["recoveryPreferredVPN"])
        XCTAssertTrue(object["requiredTunnel"] is NSNull)
    }

    func testRecoveryPreferenceRoundTrips() throws {
        let expected = ConnectionPreset(
            recoveryPreferredVPN: VPNServiceReference(
                serviceID: "service-uuid",
                displayName: "Office VPN",
                legacyIdentifier: "office"
            )
        )

        let actual = try JSONDecoder().decode(
            ConnectionPreset.self,
            from: JSONEncoder().encode(expected)
        )

        XCTAssertEqual(actual, expected)
    }

    private func decode(_ json: String) throws -> ConnectionPreset {
        try JSONDecoder().decode(
            ConnectionPreset.self,
            from: Data(json.utf8)
        )
    }
}
