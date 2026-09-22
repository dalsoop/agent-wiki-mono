import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.dualEntryApp(
    name: "AgentWikiGraph",
    guiName: "AgentWikiGraph",
    cliName: "agent-wiki-graph",
    coreDependencies: [
        .project(target: "AppPathsKit", path: "//swiftkit"),
        .project(target: "GraphEngineKit", path: "//swiftkit"),
        .project(target: "GraphRAGKit", path: "//swiftkit"),
        .project(target: "StateMirrorKit", path: "//swiftkit"),
        .project(target: "StateRootKit", path: "//swiftkit"),
        .project(target: "WikiLedgerKit", path: "//swiftkit")
    ],
    cliDependencies: [
        .project(target: "AppPathsKit", path: "//swiftkit"),
        .project(target: "AppScaffoldKit", path: "//swiftkit-appscaffold"),
        .project(target: "InteropKit", path: "//swiftkit"),
        .project(target: "LocalizationKit", path: "//swiftkit"),
        .project(target: "WikiLedgerKit", path: "//swiftkit")
    ],
    guiDependencies: [
        .project(target: "AppScaffoldKit", path: "//swiftkit-appscaffold"),
        .project(target: "DualEntryKit", path: "//swiftkit"),
        .project(target: "LaunchAtLoginKit", path: "//swiftkit"),
        .project(target: "LocalizationKit", path: "//swiftkit"),
        .project(target: "OnboardingUIKit", path: "//swiftkit"),
        .project(target: "PermissionKit", path: "//swiftkit"),
        .project(target: "SettingsUIKit", path: "//swiftkit"),
        .project(target: "SingleInstanceKit", path: "//swiftkit"),
        .project(target: "StateRootKit", path: "//swiftkit")
    ],
    testDependencies: [
        .project(target: "StateRootKit", path: "//swiftkit")
    ],
    guiResources: [
        "Packaging/AppIcon.icns",
        "Sources/AgentWikiGraph/Localization/Resources/**"
    ],
    infoPlist: .file(path: "Packaging/Info.plist"),
    entitlements: .file(path: "Packaging/AgentWikiGraph.entitlements")
)
