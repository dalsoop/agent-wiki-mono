// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "GujoAgentWikiEditor",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "agent-wiki-editor", targets: ["AgentWikiStudioCLI"]),
        .executable(name: "agent-wiki", targets: ["AgentWikiFullCLI"]),
        .executable(name: "AgentWikiStudio", targets: ["AgentWikiStudio"]),
        .library(name: "AgentWikiStudioCore", targets: ["AgentWikiStudioCore"]),
    ],
    dependencies: [
        .package(path: "../../swiftkit"),
        .package(path: "../../swiftkit-appscaffold", traits: ["GujoManaged", "SelfUpdating", "Telemetry"]),
        .package(path: "../../citationledgerkit"),
        .package(path: "../../agent-wiki-kit"),
        .package(path: "../../agent-wiki-ui"),
    ],
    targets: [
        .target(
            name: "AgentWikiStudioCore",
            dependencies: [
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "AppPathsKit", package: "swiftkit"),
            
                .product(name: "InteropKit", package: "swiftkit"),
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "PrivilegedKit", package: "swiftkit"),
                .product(name: "StateMirrorKit", package: "swiftkit"),
                .product(name: "StateRootKit", package: "swiftkit"),
                .product(name: "KnowledgeBaseWikiCore", package: "agent-wiki-kit"),
                .product(name: "PluginKit", package: "swiftkit"),
            ]
        ),
        .executableTarget(
            name: "AgentWikiStudio",
            dependencies: [
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "MenuBarPopoverUIKit", package: "swiftkit"),
                "AgentWikiStudioCore",
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "WindowChromeKit", package: "swiftkit"),
                .product(name: "SettingsUIKit", package: "swiftkit"),
                .product(name: "NoticeBannerUIKit", package: "swiftkit"),
                .product(name: "LaunchAtLoginKit", package: "swiftkit"),
                .product(name: "DualEntryKit", package: "swiftkit"),
                .product(name: "PermissionKit", package: "swiftkit"),
                .product(name: "SingleInstanceKit", package: "swiftkit"),
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
                .product(name: "KnowledgeBaseWikiUI", package: "agent-wiki-ui"),
                .product(name: "KnowledgeBaseWikiCore", package: "agent-wiki-kit"),
                .product(name: "StateRootKit", package: "swiftkit"),
            ],
            resources: [.process("Localization/Resources")]
        ),
        .executableTarget(
            name: "AgentWikiStudioCLI",
            dependencies: [
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "AppPathsKit", package: "swiftkit"),
            
                "AgentWikiStudioCore",
                .product(name: "InteropKit", package: "swiftkit"),
                .product(name: "SingleInstanceKit", package: "swiftkit"),
            ]
        ),
        .executableTarget(
            name: "AgentWikiFullCLI",
            dependencies: [
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "EndpointRouterKit", package: "swiftkit"),
                .product(name: "SelfTestKit", package: "swiftkit"),
                .product(name: "InteropKit", package: "swiftkit"),
                .product(name: "PluginKit", package: "swiftkit"),
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
                .product(name: "AgentCLIKit", package: "swiftkit"),
                .product(name: "KnowledgeBaseWikiCore", package: "agent-wiki-kit"),
                .product(name: "WikiCLIShared", package: "agent-wiki-kit"),
                .product(name: "CitationLedgerKit", package: "citationledgerkit"),
                .product(name: "AgentSurfaceKit", package: "swiftkit"),
                .product(name: "StateRootKit", package: "swiftkit"),
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "SingleInstanceKit", package: "swiftkit"),
            ],
            path: "Sources/AgentWikiFullCLI",
            resources: [
                .copy("Resources/agents"),
                .copy("Resources/plugin"),
            ]
        ),
        .testTarget(
            name: "AgentWikiStudioCoreTests",
            dependencies: [
                "AgentWikiStudioCore",
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "KnowledgeBaseWikiCore", package: "agent-wiki-kit"),
            
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
            ]
        ),
    ]
)
