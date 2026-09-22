import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "swiftkit-appscaffold",
    options: .options(disableSynthesizedResourceAccessors: true),
    settings: .settings(base: [
        "OTHER_SWIFT_FLAGS": ["$(inherited)", "-DGujoManaged", "-DTelemetry", "-package-name", "swiftkit-appscaffold"]
    ]),
    targets: [
        .target(
            name: "AppScaffoldKit",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "net.ranode.swiftkit.appscaffoldkit",
            deploymentTargets: .macOS("15.0"),
            sources: ["Sources/AppScaffoldKit/**"],
            dependencies: [
                .project(target: "FleetDeskKit", path: "//swiftkit"),
                .project(target: "AppPathsKit", path: "//swiftkit"),
                .project(target: "KeychainKit", path: "//swiftkit"),
                .project(target: "InteropKit", path: "//swiftkit"),
                .project(target: "DualEntryKit", path: "//swiftkit"),
                .project(target: "InstallHealthKit", path: "//swiftkit"),
                .project(target: "SingleInstanceKit", path: "//swiftkit"),
                .project(target: "SettingsUIKit", path: "//swiftkit"),
                .project(target: "LocalizationKit", path: "//swiftkit"),
                .project(target: "StateMirrorKit", path: "//swiftkit"),
                .project(target: "StateRootKit", path: "//swiftkit"),
                .project(target: "TenantGuardKit", path: "//swiftkit"),
                .project(target: "EndpointRouterKit", path: "//swiftkit"),
                .project(target: "GujoCoreKit", path: "//swiftkit"),
                .project(target: "PermissionKit", path: "//swiftkit"),
                .project(target: "TelemetryKit", path: "//swiftkit")
            ]
        ),
        .target(
            name: "AppScaffoldKitTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "net.ranode.swiftkit.appscaffoldkittests",
            deploymentTargets: .macOS("15.0"),
            sources: ["Tests/AppScaffoldKitTests/**"],
            dependencies: [
                .target(name: "AppScaffoldKit")
            ]
        )
    ]
)
