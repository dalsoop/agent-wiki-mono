// swift-tools-version: 6.1
import PackageDescription

// Agent Wiki shared Ledger UI (SwiftUI).
// Consumers: knowledge-base-wiki-swift (monlith shell), agent-wiki-reader, agent-wiki-studio.
let package = Package(
    name: "AgentWikiUI",
    defaultLocalization: "ko",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "KnowledgeBaseWikiUI", targets: ["KnowledgeBaseWikiUI"]),
    ],
    dependencies: [
        .package(path: "../swiftkit"),
        .package(path: "../swiftkit-appscaffold", traits: ["GujoManaged", "SelfUpdating"]),
        .package(path: "../agent-wiki-kit"),
        .package(url: "https://github.com/swiftgraphs/Grape.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "KnowledgeBaseWikiUI",
            dependencies: [
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
                .product(name: "DualEntryKit", package: "swiftkit"),
                .product(name: "KnowledgeBaseWikiCore", package: "agent-wiki-kit"),
                .product(name: "SingleInstanceKit", package: "swiftkit"),
                .product(name: "StateMirrorKit", package: "swiftkit"),
                .product(name: "Grape", package: "Grape"),
                .product(name: "SettingsUIKit", package: "swiftkit"),
                .product(name: "AgentSurfaceKit", package: "swiftkit"),
                .product(name: "InteropKit", package: "swiftkit"),
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "WindowChromeKit", package: "swiftkit"),
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "StateRootKit", package: "swiftkit"),
            ],
            path: "Sources/KnowledgeBaseWikiUI",
            resources: [.process("Resources")]
        ),
    ]
)
