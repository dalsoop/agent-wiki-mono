import Foundation

public actor FileClipboardSyncStore: ClipboardSyncStore {
    private let url: URL
    private var rows: [String: StoredClipboardClip]

    public init(url: URL) {
        self.url = url
        do {
            let data = try Data(contentsOf: url)
            let values = try JSONDecoder().decode([StoredClipboardClip].self, from: data)
            rows = Dictionary(uniqueKeysWithValues: values.map { ($0.clip.id, $0) })
        } catch {
            rows = [:]
        }
    }

    public func dirty(limit: Int) -> [StoredClipboardClip] {
        Array(rows.values.filter { $0.syncState != .synced }.sorted {
            $0.clip.updatedAt < $1.clip.updatedAt
        }.prefix(limit))
    }

    public func find(id: String) -> StoredClipboardClip? { rows[id] }

    public func upsert(_ value: StoredClipboardClip) {
        rows[value.clip.id] = value
        persist()
    }

    public func putLocal(_ clip: ClipboardClip) {
        rows[clip.id] = StoredClipboardClip(
            clip: clip, syncState: clip.deletedAt == nil ? .dirtyUpsert : .dirtyDelete)
        persist()
    }

    public func markSyncedIfUnchanged(_ value: StoredClipboardClip) {
        guard rows[value.clip.id] == value else { return }
        rows[value.clip.id]?.syncState = .synced
        persist()
    }

    public func activeClips() -> [ClipboardClip] {
        rows.values.map(\.clip).filter { $0.deletedAt == nil }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 플랫폼 저장소에 원격 상태를 투영할 때 tombstone까지 포함한 전체 상태를 반환한다.
    public func allClips() -> [ClipboardClip] {
        rows.values.map(\.clip).sorted { $0.updatedAt > $1.updatedAt }
    }

    public func removeAll() {
        rows.removeAll()
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Array(rows.values))
            try data.write(to: url, options: .atomic)
        } catch {
            // The next local change retries persistence; sync state remains available in memory.
        }
    }
}
