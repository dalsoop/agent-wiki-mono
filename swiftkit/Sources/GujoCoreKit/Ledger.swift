import Foundation

public final class Ledger: @unchecked Sendable {
    private let file: URL
    private let access: LedgerWriteAccess
    private var installed: [Int: InstalledProduct]
    private let lock = NSLock()

    public init(file: URL = AppPaths.ledgerFile, access: LedgerWriteAccess = .cloudApps) {
        self.file = file
        self.access = access
        if let decoded = JSONStores.load([InstalledProduct].self, from: file) {
            self.installed = Dictionary(uniqueKeysWithValues: decoded.map { ($0.productId, $0) })
        } else {
            self.installed = [:]
        }
    }

    public func status(for item: LibraryItem) -> LibraryStatus {
        lock.lock(); defer { lock.unlock() }
        guard let record = installed[item.product.id] else { return .notInstalled }
        if let current = item.bundle?.sha256, let was = record.bundleSha256, current != was {
            return .updateAvailable
        }
        return .installed
    }

    public func record(_ product: InstalledProduct) throws {
        lock.lock(); installed[product.productId] = product; lock.unlock()
        try persist()
    }

    public func remove(productId: Int) throws {
        lock.lock(); installed[productId] = nil; lock.unlock()
        try persist()
    }

    public func all() -> [InstalledProduct] {
        lock.lock(); defer { lock.unlock() }
        return Array(installed.values)
    }

    private func persist() throws {
        guard access.allowsWrite else { throw LedgerWriteDenied.retiredOwner }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Array(installed.values))
        try data.write(to: file, options: .atomic)
    }
}
