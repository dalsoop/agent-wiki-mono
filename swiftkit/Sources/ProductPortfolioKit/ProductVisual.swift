import Foundation

/// 비주얼 슬롯 상태 — 프롬프트만 있는 planned → 파일 경로가 붙은 generated.
/// (앱스토어 에셋 파이프라인·ComfyUI queue 와 같은 “프롬프트 선행” 패턴)
public enum ProductVisualStatus: String, Codable, CaseIterable, Sendable {
    case planned
    case generated
    case failed
}

/// 슬롯 용도. id 와 1:1 은 아니며, 같은 kind 를 여러 장 둘 수 있다.
public enum ProductVisualKind: String, Codable, CaseIterable, Sendable {
    case hero
    case screenshot
    case social
    case icon
}

/// 제품 카드에 붙는 이미지 슬롯 1개.
/// `path` 가 비어 있어도 `prompt` 로 생성 대기열에 넣을 수 있다.
public struct ProductVisual: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: ProductVisualKind
    public var status: ProductVisualStatus
    /// 예: `16:9`, `1:1`, `9:16`
    public var aspect: String
    public var prompt: String
    /// 생성된 파일 상대/절대 경로. planned 이면 nil.
    public var path: String?
    public var notes: String?

    public init(
        id: String,
        kind: ProductVisualKind,
        status: ProductVisualStatus = .planned,
        aspect: String,
        prompt: String,
        path: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.aspect = aspect
        self.prompt = prompt
        self.path = path
        self.notes = notes
    }

    /// 파일 경로가 있으면 generated 로 승격.
    public func markingGenerated(path: String) -> ProductVisual {
        var next = self
        next.path = path
        next.status = .generated
        return next
    }

    public func markingFailed(notes: String? = nil) -> ProductVisual {
        var next = self
        next.status = .failed
        if let notes { next.notes = notes }
        return next
    }
}

/// 포트폴리오 전체 비주얼 집계.
public struct VisualStats: Codable, Equatable, Sendable {
    public var planned: Int
    public var generated: Int
    public var failed: Int
    /// visuals 배열이 비어 있는 제품 수.
    public var noPlan: Int

    public init(planned: Int = 0, generated: Int = 0, failed: Int = 0, noPlan: Int = 0) {
        self.planned = planned
        self.generated = generated
        self.failed = failed
        self.noPlan = noPlan
    }

    public static func tally(from products: [Product]) -> VisualStats {
        var stats = VisualStats()
        for product in products {
            if product.visuals.isEmpty {
                stats.noPlan += 1
                continue
            }
            for slot in product.visuals {
                switch slot.status {
                case .planned: stats.planned += 1
                case .generated: stats.generated += 1
                case .failed: stats.failed += 1
                }
            }
        }
        return stats
    }
}

public struct VisualDraftResult: Codable, Equatable, Sendable {
    public let updated: Int
    public let unchanged: Int

    public init(updated: Int, unchanged: Int) {
        self.updated = updated
        self.unchanged = unchanged
    }
}

/// Product 관측 필드로 planned 슬롯 초안을 만든다 (이미지 생성은 하지 않음).
public enum ProductVisualDraftFactory {
    /// 기본 슬롯 템플릿 id 순서.
    public static let defaultSlotIDs = ["hero", "screenshot-main", "social-square"]

    public static func draftSlots(for product: Product) -> [ProductVisual] {
        let name = product.nameKo.isEmpty ? product.slug : product.nameKo
        let role = ProductCopy.isBlank(product.role)
            ? "macOS utility"
            : ProductCopy.plainRole(product.role)
        let persona = ProductCopy.isBlank(product.buyerPersona)
            ? "macOS power user"
            : product.buyerPersona
        let angle = ProductCopy.isBlank(product.salesAngle)
            ? role
            : product.salesAngle

        var slots: [ProductVisual] = [
            ProductVisual(
                id: "hero",
                kind: .hero,
                status: .planned,
                aspect: "16:9",
                prompt: [
                    "Clean product marketing hero for \"\(name)\".",
                    "One-line value: \(role).",
                    "Audience: \(persona). Pitch: \(angle).",
                    "Modern macOS app aesthetic, soft gradient, no cluttered UI chrome, no fake logos.",
                ].joined(separator: " ")
            ),
            ProductVisual(
                id: "screenshot-main",
                kind: .screenshot,
                status: .planned,
                aspect: "16:10",
                prompt: [
                    "Realistic macOS app window screenshot of \"\(name)\".",
                    "Show the primary workflow: \(role).",
                    "Native macOS look, light mode, readable Korean/English UI labels, no watermark.",
                ].joined(separator: " ")
            ),
            ProductVisual(
                id: "social-square",
                kind: .social,
                status: .planned,
                aspect: "1:1",
                prompt: [
                    "Square social card for \"\(name)\". Short headline from: \(angle).",
                    "Bold type, simple iconography, high contrast, App Store style thumbnail.",
                ].joined(separator: " ")
            ),
        ]

        // 기존 screenshotPaths 는 generated 슬롯으로 흡수 (경로 보존).
        for (index, path) in product.screenshotPaths.enumerated() {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let id = "screenshot-path-\(index)"
            if slots.contains(where: { $0.path == trimmed }) { continue }
            slots.append(
                ProductVisual(
                    id: id,
                    kind: .screenshot,
                    status: .generated,
                    aspect: "16:10",
                    prompt: "Existing screenshot imported from screenshotPaths",
                    path: trimmed
                )
            )
        }
        return slots
    }

    /// 비어 있는 visuals 만 채운다. 이미 슬롯이 있으면 유지.
    public static func applyingDraft(to product: Product, force: Bool = false) throws -> (Product, Bool) {
        if !product.visuals.isEmpty, !force {
            return (product, false)
        }
        let slots = draftSlots(for: product)
        let paths = slots.compactMap { slot -> String? in
            guard slot.status == .generated, let path = slot.path, !path.isEmpty else { return nil }
            return path
        }
        // screenshotPaths 는 generated 경로와 합집합 (기존 값 보존).
        var mergedPaths = product.screenshotPaths
        for path in paths where !mergedPaths.contains(path) {
            mergedPaths.append(path)
        }
        let next = try product.replacing(
            Product.Patch(surface: .init(screenshotPaths: mergedPaths, visuals: slots))
        )
        return (next, true)
    }

    public static func applyToStore(
        _ store: ProductStore,
        slug: String? = nil,
        force: Bool = false
    ) throws -> VisualDraftResult {
        let targets: [Product]
        if let slug {
            targets = [try store.show(slug: slug)]
        } else {
            targets = try store.list()
        }
        var updated = 0
        var unchanged = 0
        for product in targets {
            let (next, changed) = try applyingDraft(to: product, force: force)
            if changed {
                try store.save(next)
                updated += 1
            } else {
                unchanged += 1
            }
        }
        return VisualDraftResult(updated: updated, unchanged: unchanged)
    }

    /// 슬롯을 generated 로 승격하고 path 를 붙인다. screenshotPaths 에도 합친다.
    /// 홈 절대 경로는 `~/...` 포터블 형태로 저장한다.
    public static func markGenerated(
        on product: Product,
        slotID: String,
        path: String
    ) throws -> Product {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProductVisualError.emptyPath
        }
        let portable = PortfolioPath.makingPortable(trimmed)
        guard let index = product.visuals.firstIndex(where: { $0.id == slotID }) else {
            throw ProductVisualError.slotNotFound(slug: product.slug, slotID: slotID)
        }
        var slots = product.visuals
        slots[index] = slots[index].markingGenerated(path: portable)
        var shots = product.screenshotPaths
        if !shots.contains(portable) {
            shots.append(portable)
        }
        return try product.replacing(
            Product.Patch(surface: .init(screenshotPaths: shots, visuals: slots))
        )
    }

    public static func markGenerated(
        in store: ProductStore,
        slug: String,
        slotID: String,
        path: String
    ) throws -> Product {
        let next = try markGenerated(on: try store.show(slug: slug), slotID: slotID, path: path)
        try store.save(next)
        return next
    }
}

public enum ProductVisualError: Error, Equatable, LocalizedError, Sendable {
    case emptyPath
    case slotNotFound(slug: String, slotID: String)

    public var errorDescription: String? {
        switch self {
        case .emptyPath:
            "비주얼 path 는 비울 수 없습니다."
        case let .slotNotFound(slug, slotID):
            "슬롯을 찾을 수 없습니다: \(slug)#\(slotID)"
        }
    }
}
