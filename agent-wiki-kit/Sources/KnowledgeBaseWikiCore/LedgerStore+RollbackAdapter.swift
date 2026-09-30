import Foundation

extension LedgerStore {
    /// 객체 파일 존재 여부 확인
    public func hasObject(id: String) -> Bool {
        let objectsDir = root.appendingPathComponent("objects")
        guard let enumerator = FileManager.default.enumerator(
            at: objectsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return false }
        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == "\(id).md" {
            return true
        }
        return false
    }

    /// 원자적 연산 실패 시 롤백용 — 방금 쓰기 실패한 미완성 객체 파일을 제거한다.
    public func rollbackUncommittedObject(id: String, published: Date) throws {
        let calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        let components = calendar.dateComponents(in: utc, from: published)
        let year = String(format: "%04d", components.year ?? 0)
        let month = String(format: "%02d", components.month ?? 0)
        let objectsDir = root.appendingPathComponent("objects")
        let dir = objectsDir.appendingPathComponent(year).appendingPathComponent(month)
        let url = dir.appendingPathComponent("\(id).md")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            return
        }
        guard let enumerator = FileManager.default.enumerator(
            at: objectsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == "\(id).md" {
            try FileManager.default.removeItem(at: fileURL)
            return
        }
    }
}
