#if os(macOS)
import ArchitectureCityKit
import SwiftUI

public struct CityChromeCopy {
    public var used: String
    public var unused: String
    public var filter: String
    public var filterAll: String
    public var filterUsed: String
    public var filterUnused: String
    public var inspector: String
    public var click: String
    public var hint: String
    public var search: String
    public var roleAll: String
    public var districtAll: String
    public var uses: String
    public var usedBy: String
    public var legend: String
    public var reason: (CityBuilding) -> String

    public struct Counts {
        public var used: String
        public var unused: String
        public init(used: String, unused: String) {
            self.used = used
            self.unused = unused
        }
    }

    public struct FilterCopy {
        public var filter: String
        public var all: String
        public var used: String
        public var unused: String
        public init(filter: String, all: String, used: String, unused: String) {
            self.filter = filter
            self.all = all
            self.used = used
            self.unused = unused
        }
    }

    public struct InspectorCopy {
        public var inspector: String
        public var click: String
        public var hint: String
        public var search: String
        public init(inspector: String, click: String, hint: String, search: String) {
            self.inspector = inspector
            self.click = click
            self.hint = hint
            self.search = search
        }
    }

    public struct CatalogCopy {
        public var roleAll: String
        public var districtAll: String
        public var uses: String
        public var usedBy: String
        public var legend: String
        public init(
            roleAll: String,
            districtAll: String,
            uses: String,
            usedBy: String,
            legend: String
        ) {
            self.roleAll = roleAll
            self.districtAll = districtAll
            self.uses = uses
            self.usedBy = usedBy
            self.legend = legend
        }
    }

    public init(
        counts: Counts,
        filter: FilterCopy,
        inspector: InspectorCopy,
        catalog: CatalogCopy,
        reason: @escaping (CityBuilding) -> String
    ) {
        self.used = counts.used
        self.unused = counts.unused
        self.filter = filter.filter
        self.filterAll = filter.all
        self.filterUsed = filter.used
        self.filterUnused = filter.unused
        self.inspector = inspector.inspector
        self.click = inspector.click
        self.hint = inspector.hint
        self.search = inspector.search
        self.roleAll = catalog.roleAll
        self.districtAll = catalog.districtAll
        self.uses = catalog.uses
        self.usedBy = catalog.usedBy
        self.legend = catalog.legend
        self.reason = reason
    }

    /// 라벨을 납작하게 나열해 넘기던 호출부용 호환 이니셜라이저.
    /// 그룹형(`counts:filter:inspector:catalog:`) 이 정본이다.
    @_disfavoredOverload
    public init(
        used: String,
        unused: String,
        filter: String,
        filterAll: String,
        filterUsed: String,
        filterUnused: String,
        inspector: String,
        click: String,
        hint: String,
        search: String,
        roleAll: String,
        districtAll: String,
        uses: String,
        usedBy: String,
        legend: String,
        reason: @escaping (CityBuilding) -> String
    ) {
        self.init(
            counts: Counts(used: used, unused: unused),
            filter: FilterCopy(
                filter: filter, all: filterAll, used: filterUsed, unused: filterUnused),
            inspector: InspectorCopy(
                inspector: inspector, click: click, hint: hint, search: search),
            catalog: CatalogCopy(
                roleAll: roleAll, districtAll: districtAll,
                uses: uses, usedBy: usedBy, legend: legend),
            reason: reason
        )
    }
}

public struct CityFilterBar: View {
    @Binding var query: CityQuery
    var usedCount: Int
    var unusedCount: Int
    var roles: [CityRole]
    var districts: [String]
    var copy: CityChromeCopy

    public init(
        query: Binding<CityQuery>,
        usedCount: Int,
        unusedCount: Int,
        roles: [CityRole],
        districts: [String],
        copy: CityChromeCopy
    ) {
        self._query = query
        self.usedCount = usedCount
        self.unusedCount = unusedCount
        self.roles = roles
        self.districts = districts
        self.copy = copy
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("\(copy.used) \(usedCount)")
                Text("·")
                Text("\(copy.unused) \(unusedCount)")
                Spacer()
                Picker(copy.filter, selection: $query.usage) {
                    Text(copy.filterAll).tag(CityFilter.all)
                    Text(copy.filterUsed).tag(CityFilter.used)
                    Text(copy.filterUnused).tag(CityFilter.unused)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(copy.search, text: $query.text)
                    .textFieldStyle(.roundedBorder)
                Picker(copy.roleAll, selection: Binding(
                    get: { query.role },
                    set: { query.role = $0 }
                )) {
                    Text(copy.roleAll).tag(Optional<CityRole>.none)
                    ForEach(roles, id: \.self) { role in
                        Text(role.rawValue).tag(Optional(role))
                    }
                }
                .frame(maxWidth: 140)
                Picker(copy.districtAll, selection: Binding(
                    get: { query.district },
                    set: { query.district = $0 }
                )) {
                    Text(copy.districtAll).tag(Optional<String>.none)
                    ForEach(districts, id: \.self) { name in
                        Text(name).tag(Optional(name))
                    }
                }
                .frame(maxWidth: 160)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

public struct CityLegend: View {
    var roles: [CityRole]
    var copy: CityChromeCopy

    public init(roles: [CityRole], copy: CityChromeCopy) {
        self.roles = roles
        self.copy = copy
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(copy.legend).font(.caption2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 4)], alignment: .leading, spacing: 4) {
                ForEach(roles, id: \.self) { role in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(nsColor: CityPaint.color(role: role, usage: .used, face: .backend)))
                            .frame(width: 8, height: 8)
                        Text(role.rawValue).font(.system(size: 9))
                    }
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

public struct CityInspectorCard<Footer: View>: View {
    var building: CityBuilding?
    var empty: String
    var uses: [String]
    var usedBy: [String]
    var copy: CityChromeCopy
    var footer: (CityBuilding) -> Footer

    public init(
        building: CityBuilding?,
        empty: String,
        uses: [String],
        usedBy: [String],
        copy: CityChromeCopy,
        @ViewBuilder footer: @escaping (CityBuilding) -> Footer
    ) {
        self.building = building
        self.empty = empty
        self.uses = uses
        self.usedBy = usedBy
        self.copy = copy
        self.footer = footer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(copy.inspector).font(.caption.bold())
            if let building {
                Text(building.label).font(.callout.bold())
                Text("\(building.role.rawValue) · \(building.district)")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(copy.reason(building)).font(.caption2)
                    .foregroundStyle(building.usage == .unused ? .orange : .secondary)
                if !usedBy.isEmpty {
                    Text("\(copy.usedBy): \(usedBy.prefix(6).joined(separator: ", "))")
                        .font(.caption2)
                }
                if !uses.isEmpty {
                    Text("\(copy.uses): \(uses.prefix(6).joined(separator: ", "))")
                        .font(.caption2)
                }
                footer(building)
            } else {
                Text(empty).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(minWidth: 240, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

public struct CityCanvas<Footer: View>: View {
    var world: CityWorld
    var inventoryRoles: [CityRole]
    var inventoryDistricts: [String]
    @Binding var pickedId: String?
    @Binding var query: CityQuery
    var copy: CityChromeCopy
    var empty: String
    var footer: (CityBuilding) -> Footer

    public init(
        world: CityWorld,
        inventoryRoles: [CityRole],
        inventoryDistricts: [String],
        pickedId: Binding<String?>,
        query: Binding<CityQuery>,
        copy: CityChromeCopy,
        empty: String,
        @ViewBuilder footer: @escaping (CityBuilding) -> Footer
    ) {
        self.world = world
        self.inventoryRoles = inventoryRoles
        self.inventoryDistricts = inventoryDistricts
        self._pickedId = pickedId
        self._query = query
        self.copy = copy
        self.empty = empty
        self.footer = footer
    }

    public var body: some View {
        VStack(spacing: 0) {
            CityFilterBar(
                query: $query,
                usedCount: world.usedCount,
                unusedCount: world.unusedCount,
                roles: inventoryRoles,
                districts: inventoryDistricts,
                copy: copy
            )
            .background(.bar)
            Text(copy.hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            Divider()
            ZStack(alignment: .bottomTrailing) {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
                    CitySceneView(world: world, clock: t, pickedId: pickedId, onPick: { pickedId = $0 })
                }
                VStack(alignment: .trailing, spacing: 8) {
                    CityLegend(roles: inventoryRoles, copy: copy)
                    CityInspectorCard(
                        building: pickedId.flatMap { world.buildingById[$0] },
                        empty: empty,
                        uses: labels(world.uses[pickedId ?? ""] ?? []),
                        usedBy: labels(world.usedBy[pickedId ?? ""] ?? []),
                        copy: copy,
                        footer: footer
                    )
                }
                .padding(12)
            }
        }
    }

    private func labels(_ ids: [String]) -> [String] {
        ids.compactMap { world.buildingById[$0]?.label ?? $0.split(separator: ":").last.map(String.init) }
    }
}
#endif
