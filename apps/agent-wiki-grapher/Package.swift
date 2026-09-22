// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "GujoAgentWikiGrapher",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        // helpers dual-entry: PATH CLI product (never MacOS GUI)
        .executable(name: "agent-wiki-grapher", targets: ["AgentWikiGraphCLI"]),
        .executable(name: "AgentWikiGraph", targets: ["AgentWikiGraph"]),
        .library(name: "AgentWikiGraphCore", targets: ["AgentWikiGraphCore"]),
    ],
    dependencies: [
        .package(path: "../../swiftkit"),
        .package(path: "../../swiftkit-appscaffold", traits: ["GujoManaged", "SelfUpdating", "Telemetry"]),
    ],
    targets: [
        .target(
            name: "AgentWikiGraphCore",
            dependencies: [
                .product(name: "AppPathsKit", package: "swiftkit"),
            
                .product(name: "StateMirrorKit", package: "swiftkit"),
                .product(name: "StateRootKit", package: "swiftkit"),
                .product(name: "WikiLedgerKit", package: "swiftkit"),
                .product(name: "GraphEngineKit", package: "swiftkit"),
                .product(name: "GraphRAGKit", package: "swiftkit"),
            ]
        ),
        .executableTarget(
            name: "AgentWikiGraph",
            dependencies: [
                "AgentWikiGraphCore",
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "OnboardingUIKit", package: "swiftkit"),
                .product(name: "SettingsUIKit", package: "swiftkit"),
                .product(name: "LaunchAtLoginKit", package: "swiftkit"),
                .product(name: "DualEntryKit", package: "swiftkit"),
                .product(name: "PermissionKit", package: "swiftkit"),
                .product(name: "SingleInstanceKit", package: "swiftkit"),
                .product(name: "StateRootKit", package: "swiftkit"),
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
            ],
            resources: [.process("Localization/Resources")]
        ),
        // Foundation-only PATH CLI — keep AppKit out (dual-entry hang 2026-07-25)
        .executableTarget(
            name: "AgentWikiGraphCLI",
            dependencies: [
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "SingleInstanceKit", package: "swiftkit"),
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "AppPathsKit", package: "swiftkit"),
            
                .product(name: "WikiLedgerKit", package: "swiftkit"),
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
                .product(name: "InteropKit", package: "swiftkit"),
                "AgentWikiGraphCore",
            ]
        ),
        .testTarget(
            name: "AgentWikiGraphCoreTests",
            dependencies: [
                "AgentWikiGraphCore",
                .product(name: "StateRootKit", package: "swiftkit"),
            
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
            ]
        ),
    ]
)
