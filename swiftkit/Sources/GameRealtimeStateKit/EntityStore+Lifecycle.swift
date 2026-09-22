extension EntityStore {
    public mutating func spawn() throws -> EntityHandle {
        let nextStructureVersion = try incrementedStructureVersion()
        let index: UInt32

        if recycledIndices.isEmpty {
            guard generations.count < limits.totalEntities else {
                throw EntityHandleError.capacityExceeded(limit: limits.totalEntities)
            }
            index = UInt32(generations.count)
            generations.append(0)
            occupied.append(true)
        } else {
            index = recycledIndices.removeFirst()
            occupied[Int(index)] = true
        }

        let handle = EntityHandle(
            index: index,
            generation: generations[Int(index)]
        )
        commitStructureChange(version: nextStructureVersion)
        return handle
    }

    public mutating func despawn(_ handle: EntityHandle) throws {
        _ = try require(handle)
        guard handle.generation != UInt32.max else {
            throw EntityHandleError.generationWrapped
        }
        let nextStructureVersion = try incrementedStructureVersion()

        let position = Int(handle.index)
        occupied[position] = false
        generations[position] += 1
        insertRecycledIndex(handle.index)
        for storagePosition in componentStorages.indices {
            let entryPosition = Self.entityInsertionIndex(
                handle,
                in: componentStorages[storagePosition].entries
            )
            if entryPosition < componentStorages[storagePosition].entries.count,
               componentStorages[storagePosition].entries[entryPosition].entity == handle {
                componentStorages[storagePosition].entries.remove(
                    at: entryPosition
                )
            }
        }
        commitStructureChange(version: nextStructureVersion)
    }

    public mutating func registerComponentKind(
        _ kind: ComponentKind
    ) throws {
        let insertionIndex = Self.kindInsertionIndex(
            kind,
            in: registeredComponentKinds
        )
        guard insertionIndex == registeredComponentKinds.endIndex
                || registeredComponentKinds[insertionIndex] != kind
        else {
            return
        }
        guard registeredComponentKinds.count < limits.registeredComponentKinds else {
            throw EntityHandleError.registeredComponentKindsCapacityExceeded(
                limit: limits.registeredComponentKinds
            )
        }
        let nextStructureVersion = try incrementedStructureVersion()

        registeredComponentKinds.insert(kind, at: insertionIndex)
        componentStorages.insert(
            ComponentStorage(kind: kind, entries: []),
            at: insertionIndex
        )
        commitComponentChange(version: nextStructureVersion)
    }

    @discardableResult
    public mutating func attachComponent(
        _ value: ComponentValue,
        kind: ComponentKind,
        to entity: EntityHandle
    ) throws -> ComponentValue? {
        _ = try require(entity)
        let storagePosition = try registeredStorageIndex(for: kind)
        let entryPosition = Self.entityInsertionIndex(
            entity,
            in: componentStorages[storagePosition].entries
        )

        if entryPosition < componentStorages[storagePosition].entries.count,
           componentStorages[storagePosition].entries[entryPosition].entity == entity {
            let previous = componentStorages[storagePosition]
                .entries[entryPosition]
                .value
            componentStorages[storagePosition].entries[entryPosition] = EntityComponent(
                entity: entity,
                kind: kind,
                value: value
            )
            return previous
        }

        let componentCount = componentStorages[storagePosition].entries.count
        guard componentCount < limits.entitiesPerKind else {
            throw EntityHandleError.entitiesPerKindCapacityExceeded(
                kind: kind,
                limit: limits.entitiesPerKind
            )
        }
        guard componentCount < limits.componentSlotsPerKind else {
            throw EntityHandleError.componentSlotsPerKindCapacityExceeded(
                kind: kind,
                limit: limits.componentSlotsPerKind
            )
        }
        let nextStructureVersion = try incrementedStructureVersion()

        componentStorages[storagePosition].entries.insert(
            EntityComponent(entity: entity, kind: kind, value: value),
            at: entryPosition
        )
        commitComponentChange(version: nextStructureVersion)
        return nil
    }

    @discardableResult
    public mutating func removeComponent(
        kind: ComponentKind,
        from entity: EntityHandle
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
        let nextStructureVersion = try incrementedStructureVersion()
        let previous = componentStorages[storagePosition]
            .entries[entryPosition]
            .value

        componentStorages[storagePosition].entries.remove(at: entryPosition)
        commitComponentChange(version: nextStructureVersion)
        return previous
    }

    func incrementedStructureVersion() throws -> UInt64 {
        let (next, overflow) = structureVersion.addingReportingOverflow(1)
        guard !overflow else {
            throw EntityHandleError.structureVersionWrapped
        }
        return next
    }

    mutating func insertRecycledIndex(_ index: UInt32) {
        var lowerBound = recycledIndices.startIndex
        var upperBound = recycledIndices.endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if recycledIndices[middle] < index {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        let position = lowerBound
        recycledIndices.insert(index, at: position)
    }

    mutating func commitStructureChange(version: UInt64) {
        structureVersion = version
        stableQueryCache = StableQuery(
            sortedStructureVersion: version,
            sortedEntities: Self.liveHandles(
                generations: generations,
                occupied: occupied
            )
        )
        componentQueryCache.removeAll(keepingCapacity: true)
    }

    mutating func commitComponentChange(version: UInt64) {
        structureVersion = version
        stableQueryCache = StableQuery(
            sortedStructureVersion: version,
            sortedEntities: stableQueryCache.entities
        )
        componentQueryCache.removeAll(keepingCapacity: true)
    }
}
