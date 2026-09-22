import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "swiftkit-sparkle",
    targets: [
        .target(
            name: "SparkleUpdateKit",
            destinations: .macOS,
            product: .framework,
            bundleId: "net.ranode.swiftkit.sparkle",
            deploymentTargets: .macOS("15.0"),
            sources: ["Sources/SparkleUpdateKit/**"],
            resources: ["Sources/SparkleUpdateKit/Resources/**"],
            dependencies: [
                .project(target: "AppWindowKit", path: "//swiftkit"),
                .project(target: "LocalizationKit", path: "//swiftkit"),
                .project(target: "SettingsUIKit", path: "//swiftkit"),
                .sparkle,
            ]
        ),
        .target(
            name: "SparkleUpdateKitTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "net.ranode.swiftkit.sparkle.tests",
            deploymentTargets: .macOS("15.0"),
            sources: ["Tests/SparkleUpdateKitTests/**"],
            dependencies: [
                .target(name: "SparkleUpdateKit"),
            ]
        ),
    ]
)
