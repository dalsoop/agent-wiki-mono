import Foundation

public struct UpdateTarget: Sendable, Equatable {
    public let installation: Installation
    public let folder: Folder
}

public struct UpdatePlan: Sendable, Equatable {
    public let targets: [UpdateTarget]

    public static func make(targets installations: [Installation], folders: [Folder]) throws -> UpdatePlan {
        let foldersById = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        var planned: [UpdateTarget] = []
        for installation in installations {
            guard let folder = foldersById[installation.folderId] else {
                throw DownloadError(message: "update target folder missing for product \(installation.productId)")
            }
            planned.append(UpdateTarget(installation: installation, folder: folder))
        }
        guard !planned.isEmpty else {
            throw DownloadError(message: "no update targets")
        }
        return UpdatePlan(targets: planned)
    }
}
