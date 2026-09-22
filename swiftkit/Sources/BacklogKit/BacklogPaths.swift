import Foundation
import StateRootKit

public enum BacklogPaths {
    public static var defaultPortfolioRoot: URL {
        StateRootKit.url(".product-portfolio")
    }

    public static var defaultBacklogRoot: URL {
        defaultPortfolioRoot.appendingPathComponent("backlog", isDirectory: true)
    }

    public static func itemURL(for id: UUID, in root: URL = defaultBacklogRoot) -> URL {
        root.appendingPathComponent("\(id.uuidString.lowercased()).json")
    }
}
