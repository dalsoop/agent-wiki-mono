import Foundation
import Testing
@testable import LicenseCacheKit

@Suite("DeviceUUIDRegistry")
struct DeviceUUIDRegistryTests {
    @Test("set then get then list round-trips UUID files")
    func setGetListRoundTrip() throws {
        let files = MemoryLicenseFileSystem()
        let root = URL(fileURLWithPath: "/mem/net.ranode.license-devices", isDirectory: true)
        let registry = DeviceUUIDRegistry(files: files, root: root)
        try registry.set(service: "net.ranode.sample", uuid: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        let got = try registry.get(service: "net.ranode.sample")
        #expect(got?.uuid == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        let listed = try registry.list()
        #expect(listed.count == 1)
        #expect(listed[0].service == "net.ranode.sample")
    }

    @Test("default root uses Application Support directory name")
    func defaultRootPath() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let root = DeviceUUIDRegistry.defaultRoot(home: home)
        #expect(root.lastPathComponent == DeviceUUIDRegistry.directoryName)
        #expect(root.path.hasSuffix("Library/Application Support/net.ranode.license-devices"))
    }

    @Test("unsafe service names map to a stable file name")
    func safeFileName() {
        #expect(DeviceUUIDRegistry.safeFileName("net.ranode.app") == "net.ranode.app")
        #expect(DeviceUUIDRegistry.safeFileName("net/ranode app") == "net-ranode-app")
    }
}
