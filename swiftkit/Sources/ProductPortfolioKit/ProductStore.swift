import Foundation
import StateRootKit

public enum ProductStoreError: Error, Equatable, LocalizedError, Sendable {
    case alreadyExists(String)
    case notFound(String)
    case invalidFileName(String)

    public var errorDescription: String? {
        switch self {
        case let .alreadyExists(slug): "이미 존재하는 제품입니다: \(slug)"
        case let .notFound(slug): "제품을 찾을 수 없습니다: \(slug)"
        case let .invalidFileName(name): "제품 파일명과 slug가 일치하지 않습니다: \(name)"
        }
    }
}

public struct ProductStore: Sendable {
    public let rootDirectory: URL
    public let productsDirectory: URL

    public init(rootDirectory: URL = Self.defaultRootDirectory) throws {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.productsDirectory = rootDirectory
            .appendingPathComponent("products", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(
            at: productsDirectory,
            withIntermediateDirectories: true
        )
    }

    public static var defaultRootDirectory: URL {
        StateRootKit.url(for: ".product-portfolio")
    }

    public func list() throws -> [Product] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: productsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return try urls
            .filter { $0.pathExtension == "json" }
            .map { url in
                let product = try decode(url)
                guard url.deletingPathExtension().lastPathComponent == product.slug else {
                    throw ProductStoreError.invalidFileName(url.lastPathComponent)
                }
                return product
            }
            .sorted { $0.slug < $1.slug }
    }

    public func show(slug: String) throws -> Product {
        guard Product.isValidSlug(slug) else { throw ProductValidationError.invalidSlug(slug) }
        let url = productURL(slug: slug)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProductStoreError.notFound(slug)
        }
        return try decode(url)
    }

    public func add(_ product: Product) throws {
        let url = productURL(slug: product.slug)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw ProductStoreError.alreadyExists(product.slug)
        }
        try write(product, to: url)
    }

    public func save(_ product: Product) throws {
        try write(product, to: productURL(slug: product.slug))
    }

    public func contains(slug: String) -> Bool {
        guard Product.isValidSlug(slug) else { return false }
        return FileManager.default.fileExists(atPath: productURL(slug: slug).path)
    }

    private func productURL(slug: String) -> URL {
        productsDirectory.appendingPathComponent(slug).appendingPathExtension("json")
    }

    private func decode(_ url: URL) throws -> Product {
        try JSONDecoder().decode(Product.self, from: Data(contentsOf: url))
    }

    private func write(_ product: Product, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(product)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }
}
