import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.dualEntryApp(
    name: "AgentWikiGlobal",
    guiName: "AgentWikiGlobal",
    cliName: "agent-wiki-global",
    coreDependencies: [
        .project(target: "AppPathsKit", path: "//swiftkit"),
        .project(target: "CommandKit", path: "//swiftkit"),
        .project(target: "KnowledgeBaseWikiCore", path: "//agent-wiki-kit"),
        .project(target: "PluginKit", path: "//swiftkit"),
        .project(target: "StateMirrorKit", path: "//swiftkit")
    ],
    cliDependencies: [
        .project(target: "AgentCLIKit", path: "//swiftkit"),
        .project(target: "AgentSurfaceKit", path: "//swiftkit"),
        .project(target: "AppPathsKit", path: "//swiftkit"),
        .project(target: "AppScaffoldKit", path: "//swiftkit-appscaffold"),
        .project(target: "CitationLedgerKit", path: "//swiftkit"),
        .project(target: "CommandKit", path: "//swiftkit"),
        .project(target: "InteropKit", path: "//swiftkit"),
        .project(target: "KnowledgeBaseWikiCore", path: "//agent-wiki-kit"),
        .project(target: "LocalizationKit", path: "//swiftkit"),
        .project(target: "PluginKit", path: "//swiftkit"),
        .project(target: "SelfTestKit", path: "//swiftkit"),
        .project(target: "StateRootKit", path: "//swiftkit"),
        .project(target: "WikiCLIShared", path: "//agent-wiki-kit")
    ],
    guiDependencies: [
        .project(target: "AppScaffoldKit", path: "//swiftkit-appscaffold"),
        .project(target: "DualEntryKit", path: "//swiftkit"),
        .project(target: "LaunchAtLoginKit", path: "//swiftkit"),
        .project(target: "LocalizationKit", path: "//swiftkit"),
        .project(target: "MenuBarPopoverUIKit", path: "//swiftkit"),
        .project(target: "PermissionKit", path: "//swiftkit"),
        .project(target: "SettingsUIKit", path: "//swiftkit"),
        .project(target: "SingleInstanceKit", path: "//swiftkit"),
        .project(target: "SparkleUpdateKit", path: "//swiftkit-sparkle"),
        .project(target: "StateRootKit", path: "//swiftkit")
    ],
    testDependencies: [
        .project(target: "AppScaffoldKit", path: "//swiftkit-appscaffold"),
        .project(target: "CommandKit", path: "//swiftkit"),
        .project(target: "KnowledgeBaseWikiCore", path: "//agent-wiki-kit")
    ],
    guiResources: [
        "Packaging/AppIcon.icns",
        "Sources/AgentWikiGlobal/Localization/Resources/**"
    ],
    infoPlist: .file(path: "Packaging/Info.plist"),
    entitlements: .file(path: "Packaging/AgentWikiGlobal.entitlements")
)
