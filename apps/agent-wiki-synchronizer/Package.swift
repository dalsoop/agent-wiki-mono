// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "GujoAgentWikiSynchronizer",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        // helpers dual-entry: PATH CLI product (never MacOS GUI)
        .executable(name: "agent-wiki-synchronizer", targets: ["AgentWikiGlobalCLI"]),
        .executable(name: "AgentWikiGlobal", targets: ["AgentWikiGlobal"]),
        .library(name: "AgentWikiGlobalCore", targets: ["AgentWikiGlobalCore"]),
    ],
    dependencies: [
        .package(path: "../../swiftkit"),
        .package(path: "../../swiftkit-sparkle"),
        .package(path: "../../swiftkit-appscaffold", traits: ["GujoManaged", "SelfUpdating"]),
        .package(path: "../../agent-wiki-kit"),
        .package(path: "../../citationledgerkit"),
    ],
    targets: [
        .target(
            name: "AgentWikiGlobalCore",
            dependencies: [
                .product(name: "StateRootKit", package: "swiftkit"),
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "StateMirrorKit", package: "swiftkit"),
                .product(name: "AppPathsKit", package: "swiftkit"),
                .product(name: "PluginKit", package: "swiftkit"),
                .product(name: "KnowledgeBaseWikiCore", package: "agent-wiki-kit"),
            ]
        ),
        .executableTarget(
            name: "AgentWikiGlobal",
            dependencies: [
                .product(name: "MenuBarPopoverUIKit", package: "swiftkit"),
                "AgentWikiGlobalCore",
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "SettingsUIKit", package: "swiftkit"),
                .product(name: "LaunchAtLoginKit", package: "swiftkit"),
                .product(name: "SparkleUpdateKit", package: "swiftkit-sparkle"),
                .product(name: "DualEntryKit", package: "swiftkit"),
                .product(name: "PermissionKit", package: "swiftkit"),
                .product(name: "SingleInstanceKit", package: "swiftkit"),
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
                .product(name: "StateRootKit", package: "swiftkit"),
            ],
            resources: [.process("Localization/Resources")]
        ),
        // Foundation-only PATH CLI — keep AppKit out (dual-entry hang 2026-07-25)
        .executableTarget(
            name: "AgentWikiGlobalCLI",
            dependencies: [
                .product(name: "SingleInstanceKit", package: "swiftkit"),
                "AgentWikiGlobalCore",
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "WikiCLIShared", package: "agent-wiki-kit"),
                .product(name: "KnowledgeBaseWikiCore", package: "agent-wiki-kit"),
                .product(name: "CitationLedgerKit", package: "citationledgerkit"),
                .product(name: "InteropKit", package: "swiftkit"),
                .product(name: "AppPathsKit", package: "swiftkit"),
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
                .product(name: "AgentCLIKit", package: "swiftkit"),
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "AgentSurfaceKit", package: "swiftkit"),
                .product(name: "StateRootKit", package: "swiftkit"),
                .product(name: "SelfTestKit", package: "swiftkit"),
                .product(name: "PluginKit", package: "swiftkit"),
            ]
        ),
        .testTarget(
            name: "AgentWikiGlobalCoreTests",
            dependencies: [
                "AgentWikiGlobalCore",
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "KnowledgeBaseWikiCore", package: "agent-wiki-kit"),
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
            ]
        ),
    ]
)
