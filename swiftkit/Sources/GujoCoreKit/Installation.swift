import Foundation

public struct Installation: Codable, Sendable, Equatable, Identifiable {
    public let folderId: UUID
    public let productId: Int
    public let slug: String
    public let name: String
    public let bundleSha256: String?
    public let installedAt: Date
    public let sizeBytes: Int
    public var id: String { "\(folderId.uuidString):\(productId)" }
    public init(folderId: UUID, productId: Int, slug: String, name: String, bundleSha256: String?, installedAt: Date, sizeBytes: Int) {
        self.folderId = folderId
        self.productId = productId
        self.slug = slug
        self.name = name
        self.bundleSha256 = bundleSha256
        self.installedAt = installedAt
        self.sizeBytes = sizeBytes
    }

    public func installDirectory(in folder: Folder) -> URL {
        URL(fileURLWithPath: folder.path, isDirectory: true)
            .appendingPathComponent(slug, isDirectory: true)
            .standardizedFileURL
    }

    public func launchURL(in folder: Folder) -> URL {
        let installDir = installDirectory(in: folder)
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: installDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            FileHandle.standardError.write(
                Data("warning: install directory listing failed: \(error)\n".utf8))
            children = []
        }
        if let app = children
            .filter({ $0.pathExtension == "app" })
            .sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
            .first {
            return app.standardizedFileURL
        }
        return installDir
    }
}

public struct InstalledAppGroup: Sendable, Identifiable {
    public let productId: Int
    public let name: String
    public let installations: [Installation]
    public var id: Int { productId }
    public var copyCount: Int { installations.count }
    public var totalSizeBytes: Int { installations.reduce(0) { $0 + $1.sizeBytes } }

    public static func make(from installations: [Installation]) -> [InstalledAppGroup] {
        Dictionary(grouping: installations, by: \.productId)
            .map { productId, copies in
                let sortedCopies = copies.sorted {
                    if $0.installedAt == $1.installedAt {
                        return $0.folderId.uuidString < $1.folderId.uuidString
                    }
                    return $0.installedAt > $1.installedAt
                }
                return InstalledAppGroup(
                    productId: productId,
                    name: sortedCopies.first?.name ?? "App \(productId)",
                    installations: sortedCopies
                )
            }
            .sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                if order == .orderedSame { return $0.productId < $1.productId }
                return order == .orderedAscending
            }
    }
}

public final class InstallationStore: @unchecked Sendable {
    private let file: URL
    private let access: LedgerWriteAccess
    private var items: [Installation]
    private let lock = NSLock()

    public init(file: URL = AppPaths.installationsFile, access: LedgerWriteAccess = .cloudApps) {
        self.file = file
        self.access = access
        items = JSONStores.load([Installation].self, from: file) ?? []
    }

    public func all() -> [Installation] {
        lock.lock(); defer { lock.unlock() }
        return items
    }

    public func installations(inFolder folderId: UUID) -> [Installation] {
        lock.lock(); defer { lock.unlock() }
        return items.filter { $0.folderId == folderId }
    }

    public func installation(folderId: UUID, productId: Int) -> Installation? {
        lock.lock(); defer { lock.unlock() }
        return items.first { $0.folderId == folderId && $0.productId == productId }
    }

    public func installations(productId: Int, inFolderIds folderIds: Set<UUID>? = nil) -> [Installation] {
        lock.lock(); defer { lock.unlock() }
        return items.filter { installation in
            installation.productId == productId
                && (folderIds?.contains(installation.folderId) ?? true)
        }
    }

    public func installCount(productId: Int, inFolderIds folderIds: Set<UUID>? = nil) -> Int {
        installations(productId: productId, inFolderIds: folderIds).count
    }

    public func outdatedInstallations(for item: LibraryItem, inFolderIds folderIds: Set<UUID>? = nil) -> [Installation] {
        guard let current = item.bundle?.sha256 else { return [] }
        lock.lock(); defer { lock.unlock() }
        return items.filter { installation in
            installation.productId == item.product.id
                && installation.bundleSha256 != current
                && (folderIds?.contains(installation.folderId) ?? true)
        }
    }

    public func outdatedInstallations(for item: LibraryItem) -> [Installation] {
        guard let current = item.bundle?.sha256 else { return [] }
        lock.lock(); defer { lock.unlock() }
        return items.filter { $0.productId == item.product.id && $0.bundleSha256 != current }
    }

    public func record(_ installation: Installation) throws {
        lock.lock()
        items.removeAll { $0.folderId == installation.folderId && $0.productId == installation.productId }
        items.append(installation)
        let snapshot = items
        lock.unlock()
        try persist(snapshot)
    }

    public func remove(folderId: UUID, productId: Int) throws {
        lock.lock()
        items.removeAll { $0.folderId == folderId && $0.productId == productId }
        let snapshot = items
        lock.unlock()
        try persist(snapshot)
    }

    public func removeAll(inFolder folderId: UUID) throws {
        lock.lock()
        items.removeAll { $0.folderId == folderId }
        let snapshot = items
        lock.unlock()
        try persist(snapshot)
    }

    /// Aggregate status for a library card: installed if present in ≥1 folder;
    /// updateAvailable if any installed copy's sha differs from the current bundle sha.
    public func aggregateStatus(for item: LibraryItem, inFolderIds folderIds: Set<UUID>? = nil) -> LibraryStatus {
        lock.lock(); defer { lock.unlock() }
        let installs = items.filter { installation in
            installation.productId == item.product.id
                && (folderIds?.contains(installation.folderId) ?? true)
        }
        guard !installs.isEmpty else { return .notInstalled }
        if let current = item.bundle?.sha256, installs.contains(where: { $0.bundleSha256 != current }) {
            return .updateAvailable
        }
        return .installed
    }

    /// Status of a single (folder, product) pair.
    public func status(for item: LibraryItem, inFolder folderId: UUID) -> LibraryStatus {
        guard let inst = installation(folderId: folderId, productId: item.product.id) else { return .notInstalled }
        if let current = item.bundle?.sha256, inst.bundleSha256 != current { return .updateAvailable }
        return .installed
    }

    /// One-time import of the legacy flat ledger.json into the given folder. Runs only when this
    /// store has no persisted file yet. The legacy installer used `productsDir/<id>` (which is also
    /// the render cache root), so the imported slug is `"<id>"` to point removal at that same dir —
    /// removing a legacy-imported install therefore clears `productsDir/<id>` (cache regenerates on
    /// next view). New installs use ProgramSlug and live under the user's chosen folder instead.
    public func migrateLegacyLedger(from legacyFile: URL, into folder: Folder) throws {
        if FileManager.default.fileExists(atPath: file.path) { return }
        guard let legacy = JSONStores.load([InstalledProduct].self, from: legacyFile),
              !legacy.isEmpty else { return }
        lock.lock()
        for p in legacy {
            items.append(Installation(folderId: folder.id, productId: p.productId, slug: "\(p.productId)",
                                      name: p.name, bundleSha256: p.bundleSha256, installedAt: p.installedAt, sizeBytes: p.sizeBytes))
        }
        let snapshot = items
        lock.unlock()
        try persist(snapshot)
    }

    // Encodes a snapshot taken under the lock — reading `items` here instead
    // would race with concurrent mutations (e.g. Update All installing several
    // products at once) and could persist a mid-mutation array.
    private func persist(_ snapshot: [Installation]) throws {
        guard access.allowsWrite else { throw LedgerWriteDenied.retiredOwner }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONStores.encoder().encode(snapshot).write(to: file, options: .atomic)
    }

    public func clear() throws {
        lock.lock()
        items.removeAll()
        lock.unlock()
        guard access.allowsWrite else { throw LedgerWriteDenied.retiredOwner }
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }
}
