import Foundation
import LocalizationKit

public struct ProductActivityBook: Sendable, Equatable {
    private var entries: [Int: [UUID: String]] = [:]

    public init() {}

    public var isBusy: Bool {
        entries.values.contains { !$0.isEmpty }
    }

    @discardableResult
    public mutating func begin(productId: Int, label: String) -> UUID {
        let token = UUID()
        entries[productId, default: [:]][token] = label
        return token
    }

    public mutating func end(productId: Int, token: UUID) {
        entries[productId]?[token] = nil
        if let current = entries[productId], current.isEmpty {
            entries[productId] = nil
        }
    }

    public func label(productId: Int) -> String? {
        guard let productEntries = entries[productId], !productEntries.isEmpty else { return nil }
        if productEntries.count > 1 {
            return CLILocalization.format("ProductActivityBook.return", productEntries.count)
        }
        return productEntries.values.first
    }
}
