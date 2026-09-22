extension EntityStore {
    public func require(_ handle: EntityHandle) throws -> EntityHandle {
        let position = Int(handle.index)
        guard position < generations.count,
              occupied[position],
              generations[position] == handle.generation
        else {
            throw EntityHandleError.staleHandle(handle)
        }
        return handle
    }

    public func queryAll() -> [EntityHandle] {
        stableQueryCache.entities
    }

    public func stableQuery() -> StableQuery {
        stableQueryCache
    }

    public func component(
        kind: ComponentKind,
        for entity: EntityHandle
    ) throws -> ComponentValue? {
        _ = try require(entity)
        let storagePosition = try registeredStorageIndex(for: kind)
        let entryPosition = Self.entityInsertionIndex(
            entity,
            in: componentStorages[storagePosition].entries
        )
        guard entryPosition < componentStorages[storagePosition].entries.count,
              componentStorages[storagePosition].entries[entryPosition].entity == entity
        else {
            return nil
        }
        return componentStorages[storagePosition].entries[entryPosition].value
    }

    public mutating func stableQuery(
        requiring requiredKinds: [ComponentKind]
    ) throws -> StableQuery {
        let canonicalKinds = try canonicalRequiredKinds(requiredKinds)
        guard !canonicalKinds.isEmpty else {
            return stableQueryCache
        }
        let cachePosition = Self.queryCacheInsertionIndex(
            canonicalKinds,
            in: componentQueryCache
        )
        if cachePosition < componentQueryCache.count,
           componentQueryCache[cachePosition].requiredKinds == canonicalKinds {
            return componentQueryCache[cachePosition].query
        }
        guard componentQueryCache.count < limits.stableQueryCacheEntries else {
            throw EntityHandleError.stableQueryCacheCapacityExceeded(
                limit: limits.stableQueryCacheEntries
            )
        }

        var matchingEntities = componentStorages[
            try registeredStorageIndex(for: canonicalKinds[0])
        ].entries.map(\.entity)
        for kind in canonicalKinds.dropFirst() {
            let nextEntities = componentStorages[
                try registeredStorageIndex(for: kind)
            ].entries.map(\.entity)
            matchingEntities = Self.intersection(
                matchingEntities,
                nextEntities
            )
            if matchingEntities.isEmpty {
                break
            }
        }
        let query = StableQuery(
            sortedStructureVersion: structureVersion,
            sortedEntities: matchingEntities
        )
        let entry = ComponentQueryCacheEntry(
            requiredKinds: canonicalKinds,
            query: query
        )
        componentQueryCache.insert(entry, at: cachePosition)
        return query
    }

    func registeredStorageIndex(
        for kind: ComponentKind
    ) throws -> Int {
        let position = Self.kindInsertionIndex(
            kind,
            in: registeredComponentKinds
        )
        guard position < registeredComponentKinds.count,
              registeredComponentKinds[position] == kind
        else {
            throw EntityHandleError.unregisteredComponentKind(kind)
        }
        return position
    }

    func canonicalRequiredKinds(
        _ kinds: [ComponentKind]
    ) throws -> [ComponentKind] {
        let canonicalKinds = Self.unique(kinds.sorted())
        for kind in canonicalKinds {
            _ = try registeredStorageIndex(for: kind)
        }
        return canonicalKinds
    }
}
