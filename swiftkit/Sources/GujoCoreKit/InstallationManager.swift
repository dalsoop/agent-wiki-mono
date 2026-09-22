import Foundation

public final class InstallationManager: Sendable {
    private let installations: InstallationStore

    public init(installations: InstallationStore) {
        self.installations = installations
    }

    public func remove(from folder: Folder, productId: Int) throws {
        if let inst = installations.installation(folderId: folder.id, productId: productId) {
            let dir = inst.installDirectory(in: folder)
            if FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.removeItem(at: dir)
            }
        }
        try installations.remove(folderId: folder.id, productId: productId)
    }
}
