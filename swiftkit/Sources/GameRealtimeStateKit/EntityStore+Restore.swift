extension EntityStore {
    static func validate(limits: RealtimeLimits) throws {
        guard limits.totalEntities >= 0,
              limits.totalEntities <= Int(UInt32.max),
              limits.entitiesPerKind >= 0,
              limits.componentSlotsPerKind >= 0,
              limits.registeredComponentKinds >= 0,
              limits.stableQueryCacheEntries >= 0
        else {
            throw EntityHandleError.invalidLimit(
                totalEntities: limits.totalEntities
            )
        }
    }

    static func validateRestoredComponents(
        _ components: [EntityComponent],
        generations: [UInt32],
        occupied: [Bool],
        registeredKinds: [ComponentKind],
        limits: RealtimeLimits
    ) throws {
        var previous: EntityComponent?
        var countedKind: ComponentKind?
        var countForKind = 0
        for component in components {
            let position = Int(component.entity.index)
            let kindPosition = kindInsertionIndex(
                component.kind,
                in: registeredKinds
            )
            guard position < generations.count,
                  occupied[position],
                  generations[position] == component.entity.generation,
                  kindPosition < registeredKinds.count,
                  registeredKinds[kindPosition] == component.kind,
                  previous.map({
                      $0.kind != component.kind || $0.entity != component.entity
                  }) ?? true
            else {
                throw EntityStoreRestorationError.invalidState
            }
            if countedKind == component.kind {
                countForKind += 1
            } else {
                countedKind = component.kind
                countForKind = 1
            }
            guard countForKind <= limits.entitiesPerKind,
                  countForKind <= limits.componentSlotsPerKind
            else {
                throw EntityStoreRestorationError.invalidState
            }
            previous = component
        }
    }

    static func makeComponentStorages(
        registeredKinds: [ComponentKind],
        components: [EntityComponent]
    ) -> [ComponentStorage] {
        var storages = registeredKinds.map {
            ComponentStorage(kind: $0, entries: [])
        }
        for component in components {
            let position = kindInsertionIndex(
                component.kind,
                in: registeredKinds
            )
            storages[position].entries.append(component)
        }
        return storages
    }

    static func liveHandles(
        generations: [UInt32],
        occupied: [Bool]
    ) -> [EntityHandle] {
        occupied.indices.compactMap { position in
            guard occupied[position] else {
                return nil
            }
            return EntityHandle(
                index: UInt32(position),
                generation: generations[position]
            )
        }
    }
}
