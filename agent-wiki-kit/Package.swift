// swift-tools-version: 6.1
import PackageDescription

// Agent Wiki shared Core (ledger, dual-entry profile helpers used by CLI/GUI).
// Consumers: knowledge-base-wiki-swift (GUI), agent-wiki-studio-swift (full CLI), later reader.
let package = Package(
    name: "AgentWikiKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BlobStoreKit", targets: ["BlobStoreKit"]),
        .library(name: "KnowledgeBaseWikiCore", targets: ["KnowledgeBaseWikiCore"]),
        .library(name: "WikiCLIShared", targets: ["WikiCLIShared"]),
    ],
    dependencies: [
        .package(path: "../swiftkit"),
        .package(path: "../citationledgerkit"),
    ],
    targets: [
        .target(
            name: "BlobStoreKit"
        ),
        .target(
            name: "KnowledgeBaseWikiCore",
            dependencies: [
                "BlobStoreKit",
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "EndpointRouterKit", package: "swiftkit"),
                .product(name: "SigV4Kit", package: "swiftkit"),
                .product(name: "CitationLedgerKit", package: "citationledgerkit"),
                .product(name: "DualEntryKit", package: "swiftkit"),
                .product(name: "AgentSurfaceKit", package: "swiftkit"),
                .product(name: "FileBrowserKit", package: "swiftkit"),
                .product(name: "RepositoryIdentityKit", package: "swiftkit"),
                .product(name: "StateRootKit", package: "swiftkit"),
                .product(name: "SelfTestKit", package: "swiftkit"),
                .product(name: "InteropKit", package: "swiftkit"),
            ],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "WikiCLIShared",
            dependencies: [
                "KnowledgeBaseWikiCore",
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "InteropKit", package: "swiftkit"),
                .product(name: "StateRootKit", package: "swiftkit"),
                .product(name: "AgentSurfaceKit", package: "swiftkit"),
                .product(name: "LocalizationKit", package: "swiftkit"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "KnowledgeBaseWikiCoreTests",
            dependencies: ["KnowledgeBaseWikiCore"],
            path: "Tests/KnowledgeBaseWikiCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
