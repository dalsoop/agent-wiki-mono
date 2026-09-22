import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.dualEntryApp(
    name: "Agent Wiki Reader",
    guiName: "AgentWikiReader",
    cliName: "agent-wiki-reader",
    coreDependencies: [
        .project(target: "AppPathsKit", path: "//swiftkit"),
        .project(target: "CommandKit", path: "//swiftkit"),
        .project(target: "InteropKit", path: "//swiftkit"),
        .project(target: "KnowledgeBaseWikiCore", path: "//agent-wiki-kit"),
        .project(target: "LocalizationKit", path: "//swiftkit"),
        .project(target: "PrivilegedKit", path: "//swiftkit"),
        .project(target: "StateMirrorKit", path: "//swiftkit")
    ],
    cliDependencies: [
        .project(target: "AppPathsKit", path: "//swiftkit"),
        .project(target: "AppScaffoldKit", path: "//swiftkit-appscaffold"),
        .project(target: "InteropKit", path: "//swiftkit"),
        .project(target: "LocalizationKit", path: "//swiftkit")
    ],
    guiDependencies: [
        .project(target: "AppScaffoldKit", path: "//swiftkit-appscaffold"),
        .project(target: "DualEntryKit", path: "//swiftkit"),
        .project(target: "KnowledgeBaseWikiCore", path: "//agent-wiki-kit"),
        .project(target: "KnowledgeBaseWikiUI", path: "//agent-wiki-ui"),
        .project(target: "LaunchAtLoginKit", path: "//swiftkit"),
        .project(target: "LocalizationKit", path: "//swiftkit"),
        .project(target: "MenuBarPopoverUIKit", path: "//swiftkit"),
        .project(target: "NoticeBannerUIKit", path: "//swiftkit"),
        .project(target: "PermissionKit", path: "//swiftkit"),
        .project(target: "SettingsUIKit", path: "//swiftkit"),
        .project(target: "SingleInstanceKit", path: "//swiftkit"),
        .project(target: "StateRootKit", path: "//swiftkit"),
        .project(target: "WindowChromeKit", path: "//swiftkit")
    ],
    testDependencies: [
        .project(target: "CommandKit", path: "//swiftkit")
    ],
    guiResources: [
        "Packaging/AppIcon.icns",
        "Sources/AgentWikiReader/Localization/Resources/**"
    ],
    infoPlist: .file(path: "Packaging/Info.plist"),
    entitlements: .file(path: "Packaging/AgentWikiReader.entitlements")
)
