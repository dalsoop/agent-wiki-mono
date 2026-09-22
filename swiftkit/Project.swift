import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "swiftkit",
    options: .options(disableSynthesizedResourceAccessors: true),
    settings: .settings(base: [
        "OTHER_SWIFT_FLAGS": ["$(inherited)", "-package-name", "swiftkit"]
    ]),
    targets: Target.swiftKitTargetsPart1
        + Target.swiftKitTargetsPart2
        + Target.swiftKitTargetsPart3
        + Target.swiftKitTargetsPart4
        + Target.swiftKitTargetsPart5
        + Target.swiftKitTargetsPart6
)