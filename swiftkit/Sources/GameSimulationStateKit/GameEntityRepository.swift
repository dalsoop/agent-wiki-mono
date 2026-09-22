import Foundation

public enum GameEntityRepositoryError: Error, Equatable, Sendable {
    case emptyID
    case duplicateID(GameEntityID)
    case missingEntity(GameEntityID)
    case missingParent(GameEntityID)
    case selfParent(GameEntityID)
    case cycle(entityID: GameEntityID, parentID: GameEntityID)

    public var code: String {
        switch self {
        case .emptyID: "entity.empty-id"
        case .duplicateID: "entity.duplicate-id"
        case .missingEntity: "entity.missing"
        case .missingParent: "entity.missing-parent"
        case .selfParent: "entity.self-parent"
        case .cycle: "entity.parent-cycle"
        }
    }
}

public struct GameEntityRepository: Codable, Equatable, Sendable {
    public private(set) var entities: [GameEntityID: GameEntityRecord]
    public private(set) var rootIDs: [GameEntityID]
    private var childrenByParent: [GameEntityID: [GameEntityID]]
    private var tagIndex: [String: Set<GameEntityID>]

    public init() {
        entities = [:]
        rootIDs = []
        childrenByParent = [:]
        tagIndex = [:]
    }

    private enum CodingKeys: String, CodingKey {
        case records
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let records = try container.decode([GameEntityRecord].self, forKey: .records)
        self.init()
        do {
            for record in records {
                try add(record)
            }
        } catch let error as GameEntityRepositoryError {
            throw DecodingError.dataCorruptedError(
                forKey: .records,
                in: container,
                debugDescription: error.code
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var orderedRecords: [GameEntityRecord] = []
        var visited: Set<GameEntityID> = []

        func appendSubtree(_ entityID: GameEntityID) throws {
            guard visited.insert(entityID).inserted,
                  let record = entities[entityID] else {
                throw EncodingError.invalidValue(
                    entityID,
                    .init(
                        codingPath: encoder.codingPath,
                        debugDescription: "repository hierarchy is inconsistent"
                    )
                )
            }
            orderedRecords.append(record)
            for childID in childrenByParent[entityID] ?? [] {
                try appendSubtree(childID)
            }
        }

        for rootID in rootIDs {
            try appendSubtree(rootID)
        }
        guard visited.count == entities.count else {
            throw EncodingError.invalidValue(
                entities,
                .init(
                    codingPath: encoder.codingPath,
                    debugDescription: "repository contains unreachable entities"
                )
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(orderedRecords, forKey: .records)
    }

    public subscript(id: GameEntityID) -> GameEntityRecord? {
        entities[id]
    }

    public var entityIDs: [GameEntityID] {
        entities.keys.sorted()
    }

    public func childIDs(of parentID: GameEntityID) -> [GameEntityID] {
        childrenByParent[parentID] ?? []
    }

    public func entityIDs(tagged tag: String) -> [GameEntityID] {
        (tagIndex[tag] ?? []).sorted()
    }

    public mutating func add(_ record: GameEntityRecord) throws {
        guard !record.id.rawValue.isEmpty else {
            throw GameEntityRepositoryError.emptyID
        }
        guard entities[record.id] == nil else {
            throw GameEntityRepositoryError.duplicateID(record.id)
        }
        if let parentID = record.parentID, entities[parentID] == nil {
            throw GameEntityRepositoryError.missingParent(parentID)
        }

        entities[record.id] = record
        if let parentID = record.parentID {
            childrenByParent[parentID, default: []].append(record.id)
        } else {
            rootIDs.append(record.id)
        }
        for tag in record.tags {
            tagIndex[tag, default: []].insert(record.id)
        }
    }

    public mutating func setParent(
        of entityID: GameEntityID,
        to parentID: GameEntityID?
    ) throws {
        guard var record = entities[entityID] else {
            throw GameEntityRepositoryError.missingEntity(entityID)
        }
        if let parentID {
            guard entities[parentID] != nil else {
                throw GameEntityRepositoryError.missingParent(parentID)
            }
            guard parentID != entityID else {
                throw GameEntityRepositoryError.selfParent(entityID)
            }
            guard !descendants(of: entityID).contains(parentID) else {
                throw GameEntityRepositoryError.cycle(entityID: entityID, parentID: parentID)
            }
        }
        guard record.parentID != parentID else { return }

        if let oldParentID = record.parentID {
            childrenByParent[oldParentID]?.removeAll { $0 == entityID }
            removeEmptyChildrenEntry(for: oldParentID)
        } else {
            rootIDs.removeAll { $0 == entityID }
        }

        if let parentID {
            childrenByParent[parentID, default: []].append(entityID)
        } else {
            rootIDs.append(entityID)
        }
        record.parentID = parentID
        entities[entityID] = record
    }

    public mutating func addTag(_ tag: String, to entityID: GameEntityID) throws {
        guard var record = entities[entityID] else {
            throw GameEntityRepositoryError.missingEntity(entityID)
        }
        guard record.tags.insert(tag).inserted else { return }
        entities[entityID] = record
        tagIndex[tag, default: []].insert(entityID)
    }

    public mutating func removeTag(_ tag: String, from entityID: GameEntityID) throws {
        guard var record = entities[entityID] else {
            throw GameEntityRepositoryError.missingEntity(entityID)
        }
        guard record.tags.remove(tag) != nil else { return }
        entities[entityID] = record
        tagIndex[tag]?.remove(entityID)
        if tagIndex[tag]?.isEmpty == true {
            tagIndex[tag] = nil
        }
    }

    public func descendants(of entityID: GameEntityID) -> [GameEntityID] {
        guard entities[entityID] != nil else { return [] }
        var result: [GameEntityID] = []
        appendDescendants(of: entityID, to: &result)
        return result
    }

    public func removalOrder(rootedAt entityID: GameEntityID) throws -> [GameEntityID] {
        guard entities[entityID] != nil else {
            throw GameEntityRepositoryError.missingEntity(entityID)
        }
        var result: [GameEntityID] = []
        appendRemovalOrder(rootedAt: entityID, to: &result)
        return result
    }

    @discardableResult
    public mutating func removeSubtree(rootedAt entityID: GameEntityID) throws -> [GameEntityID] {
        let order = try removalOrder(rootedAt: entityID)
        let parentID = entities[entityID]?.parentID

        if let parentID {
            childrenByParent[parentID]?.removeAll { $0 == entityID }
            removeEmptyChildrenEntry(for: parentID)
        } else {
            rootIDs.removeAll { $0 == entityID }
        }

        for id in order {
            if let record = entities[id] {
                for tag in record.tags {
                    tagIndex[tag]?.remove(id)
                    if tagIndex[tag]?.isEmpty == true {
                        tagIndex[tag] = nil
                    }
                }
            }
            entities[id] = nil
            childrenByParent[id] = nil
        }
        return order
    }

    private func appendDescendants(
        of parentID: GameEntityID,
        to result: inout [GameEntityID]
    ) {
        for childID in childrenByParent[parentID] ?? [] {
            result.append(childID)
            appendDescendants(of: childID, to: &result)
        }
    }

    private func appendRemovalOrder(
        rootedAt entityID: GameEntityID,
        to result: inout [GameEntityID]
    ) {
        for childID in childrenByParent[entityID] ?? [] {
            appendRemovalOrder(rootedAt: childID, to: &result)
        }
        result.append(entityID)
    }

    private mutating func removeEmptyChildrenEntry(for parentID: GameEntityID) {
        if childrenByParent[parentID]?.isEmpty == true {
            childrenByParent[parentID] = nil
        }
    }
}
