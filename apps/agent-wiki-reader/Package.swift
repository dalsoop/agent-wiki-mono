// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "GujoAgentWikiReader",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        // helpers dual-entry: PATH CLI product (never MacOS GUI)
        .executable(name: "agent-wiki-reader", targets: ["AgentWikiReaderCLI"]),
        .executable(name: "AgentWikiReader", targets: ["AgentWikiReader"]),
        .library(name: "AgentWikiReaderCore", targets: ["AgentWikiReaderCore"]),
    ],
    dependencies: [
        .package(path: "../../swiftkit"),
        .package(path: "../../swiftkit-appscaffold", traits: ["GujoManaged", "SelfUpdating", "Telemetry"]),
        .package(path: "../../agent-wiki-kit"),
        // 원장 LedgerArea UI (monlith 와 공유)
        .package(path: "../../agent-wiki-ui"),
    ],
    targets: [
        .target(
            name: "AgentWikiReaderCore",
            dependencies: [
                .product(name: "LocalizationKit", package: "swiftkit"), 
                .product(name: "AppPathsKit", package: "swiftkit"),
            
                .product(name: "InteropKit", package: "swiftkit"),
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "PrivilegedKit", package: "swiftkit"),
                .product(name: "StateMirrorKit", package: "swiftkit"),
                .product(name: "KnowledgeBaseWikiCore", package: "agent-wiki-kit"),
            ]
        ),
        .executableTarget(
            name: "AgentWikiReader",
            dependencies: [
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "MenuBarPopoverUIKit", package: "swiftkit"),
                "AgentWikiReaderCore",
                .product(name: "StateRootKit", package: "swiftkit"),
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "SettingsUIKit", package: "swiftkit"),
                .product(name: "NoticeBannerUIKit", package: "swiftkit"),
                .product(name: "LaunchAtLoginKit", package: "swiftkit"),
                .product(name: "DualEntryKit", package: "swiftkit"),
                .product(name: "PermissionKit", package: "swiftkit"),
                .product(name: "SingleInstanceKit", package: "swiftkit"),
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
                .product(name: "KnowledgeBaseWikiUI", package: "agent-wiki-ui"),
                .product(name: "KnowledgeBaseWikiCore", package: "agent-wiki-kit"),
                .product(name: "WindowChromeKit", package: "swiftkit"),
            ],
            resources: [.process("Localization/Resources")]
        ),
        // Foundation-only PATH CLI — keep AppKit out (dual-entry hang 2026-07-25)
        .executableTarget(
            name: "AgentWikiReaderCLI",
            dependencies: [
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "SingleInstanceKit", package: "swiftkit"),
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "AppPathsKit", package: "swiftkit"),
            
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
                "AgentWikiReaderCore",
                .product(name: "InteropKit", package: "swiftkit"),
            ]
        ),
        .testTarget(
            name: "AgentWikiReaderCoreTests",
            dependencies: [
                "AgentWikiReaderCore",
                .product(name: "CommandKit", package: "swiftkit"),
            
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
            ]
        ),
    ]
)
