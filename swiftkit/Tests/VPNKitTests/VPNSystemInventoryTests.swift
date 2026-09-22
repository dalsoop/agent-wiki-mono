import XCTest
import CommandKit
@testable import VPNKit

final class VPNSystemInventoryTests: XCTestCase {
    private let list = """
    Available network connection services in the current set (*=enabled):
    * (Connected) AC17EE48-D976-47F4-A9ED-F6085F11D04C VPN (com.wireguard.macos) "official wg [VPN:com.wireguard.macos]
    * (Connected) 2E67CA98-0F9D-4964-A04B-D72D9ECC97C0 VPN (net.ranode.wireguard) "our wg" [VPN:net.ranode.wireguard]
    * (Disconnected) 11111111-2222-3333-4444-555555555555 VPN (com.apple.ipsec) "office ikev2" [VPN:com.apple.ipsec]
    """

    func testParseListKeepsEveryVPNProvider() {
        let services = VPNSystemInventory.parseList(list)
        XCTAssertEqual(services.map(\.providerBundleID), [
            "com.wireguard.macos", "net.ranode.wireguard", "com.apple.ipsec",
        ])
        XCTAssertEqual(services[0].name, "official wg")
        XCTAssertEqual(services[2].status, .disconnected)
    }

    func testParseStatusFindsInterface() {
        let status = """
        Connected
        Extended Status <dictionary> {
          IPv4 : <dictionary> {
            InterfaceName : utun5
          }
        }
        """
        XCTAssertEqual(VPNSystemInventory.parseInterface(status), "utun5")
    }

    func testLoadServicesDistinguishesSuccessfulEmptyList() async throws {
        let inventory = VPNSystemInventory(
            runner: FixedCommandRunner(
                .init(
                    stdout: "Available network connection services in the current set",
                    stderr: "",
                    exitCode: 0
                )
            )
        )

        let services = try await inventory.loadServices()

        XCTAssertEqual(services, [])
    }

    func testLoadServicesThrowsWhenListCommandFails() async {
        let inventory = VPNSystemInventory(
            runner: FixedCommandRunner(
                .init(
                    stdout: "",
                    stderr: "scutil unavailable",
                    exitCode: 72
                )
            )
        )

        do {
            _ = try await inventory.loadServices()
            XCTFail("expected inventory execution failure")
        } catch {
            XCTAssertEqual(
                error as? VPNInventoryError,
                .commandFailed(exitCode: 72, message: "scutil unavailable")
            )
        }
    }

    func testNonthrowingServicesPreservesUICompatibilityOnFailure() async {
        let inventory = VPNSystemInventory(
            runner: FixedCommandRunner(
                .init(stdout: "", stderr: "failed", exitCode: 1)
            )
        )

        let services = await inventory.services()
        XCTAssertEqual(services, [])
    }
}

private struct FixedCommandRunner: CommandRunning {
    let result: CommandResult

    init(_ result: CommandResult) {
        self.result = result
    }

    func run(
        _ launchPath: String,
        _ arguments: [String],
        timeout: TimeInterval?
    ) async -> CommandResult {
        result
    }
}
