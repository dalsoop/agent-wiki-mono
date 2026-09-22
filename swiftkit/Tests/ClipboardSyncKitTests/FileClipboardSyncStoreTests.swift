import Foundation
import Testing

@testable import ClipboardSyncKit

@Suite("File clipboard sync store")
struct FileClipboardSyncStoreTests {
    @Test func tombstonesRemainAvailableForPlatformProjection() async {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "clipboard-sync-store-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileClipboardSyncStore(url: url)
        let deleted = ClipboardClip(
            id: "018f0000-0000-7000-8000-000000000001",
            createdAt: 1,
            updatedAt: 2,
            sourceDeviceId: "remote",
            text: "deleted text",
            isFavorite: false,
            deletedAt: 2)

        await store.upsert(StoredClipboardClip(clip: deleted, syncState: .synced))

        #expect(await store.activeClips().isEmpty)
        #expect(await store.allClips() == [deleted])
    }
}
