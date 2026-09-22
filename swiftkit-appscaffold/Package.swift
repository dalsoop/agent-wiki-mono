// swift-tools-version: 6.1
import PackageDescription

// 앱 공용 스캐폴드(`RanodeApp`) — 횡단 관심사를 한 곳에 모은다.
//
// **왜 swiftkit 안이 아니라 별도 패키지인가.**
// 판매 앱은 자동 업데이트(Sparkle)가 사실상 필수인데, swiftkit 본체는 "외부 의존성 0건"을
// 불변량으로 지킨다(모든 앱이 swiftkit 을 끌기 때문). 그래서 Sparkle 은 swiftkit-sparkle 에만
// 있고, 그 패키지는 swiftkit(AppWindowKit)에 의존한다.
//
// 스캐폴드를 swiftkit 안에 두고 Sparkle 을 의존하면 패키지 수준 순환이 된다 — 실측:
//
//     error: cyclic dependency declaration found: app -> Core -> Wrap -> Core
//
// trait 로 꺼놔도 매니페스트 그래프에서 순환으로 잡힌다. 그래서 스캐폴드를 세 번째
// 패키지로 빼서 DAG 로 만든다(appscaffold → swiftkit, appscaffold → sparkle → swiftkit).
//
// 부수 효과: tools-version 6.1(traits) 이 이 패키지에만 필요하다. swiftkit 과 249개 앱은
// 6.0 그대로 둔다.
//
// **트레잇 정본은 이 패키지다(상위 선언·하위 무설정).** 함대 기본은 아래 `traits:` 의
// `.default(enabledTraits:)` 한 곳에서 정한다. 앱은 트레잇을 스스로 적지 않는다:
//
//     .package(path: "../../swiftkit-appscaffold")
//
// SPM 규칙상 소비자가 `traits:` 를 직접 적으면 기본값은 **꺼진다**. 기본과 다른 조합이
// 필요한 앱만 예외로 직접 적고, 그 이유를 매니페스트에 남긴다.
//
// 실측(6.2.4): off 면 SparkleUpdateKit 모듈이 **빌드되지 않고** 바이너리 심볼도 0이다.
// 즉 안 켠 앱에서는 "외부 의존성 0" 이 유지된다.
let package = Package(
    name: "swiftkit-appscaffold",
    defaultLocalization: "en",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "AppScaffoldKit", targets: ["AppScaffoldKit"]),
    ],
    traits: [
        // 정본은 상위(이 패키지)다. 앱은 `.package(path: "../../swiftkit-appscaffold")` 만
        // 적고 트레잇을 스스로 설정하지 않는다 — 함대 기본은 여기서 한 번 정한다.
        .default(enabledTraits: ["GujoManaged", "SelfUpdating", "Telemetry"]),
        .trait(
            name: "GujoManaged",
            description: "Gujo Cloud Apps 가 관리하는 앱(설치·연결·사용가능 판정을 Cloud Apps 에 묻는다)."),
        .trait(
            name: "SelfUpdating",
            description: "Sparkle 자동 업데이트를 스캐폴드에 포함한다(판매 앱)."),
        .trait(
            name: "Telemetry",
            description: "TelemetryKit(sentry-cocoa) 크래시/에러 수집을 bootstrap에 포함한다. DSN 없으면 no-op."),
    ],
    dependencies: [
        .package(path: "../swiftkit"),
        .package(path: "../swiftkit-sparkle"),
    ],
    targets: [
        .target(
            name: "AppScaffoldKit",
            dependencies: [
                .product(name: "FleetDeskKit", package: "swiftkit"),
                .product(name: "AppPathsKit", package: "swiftkit"),
                .product(name: "KeychainKit", package: "swiftkit"),
                .product(name: "InteropKit", package: "swiftkit"),
                .product(name: "DualEntryKit", package: "swiftkit"),
                .product(name: "InstallHealthKit", package: "swiftkit"),
                .product(name: "SingleInstanceKit", package: "swiftkit"),
                .product(name: "SettingsUIKit", package: "swiftkit"),
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "StateMirrorKit", package: "swiftkit"),
                .product(name: "StateRootKit", package: "swiftkit"),
                .product(name: "TenantGuardKit", package: "swiftkit"),
                .product(name: "EndpointRouterKit", package: "swiftkit"),
                .product(name: "GujoCoreKit", package: "swiftkit"),
                .product(
                    name: "PermissionKit", package: "swiftkit",
                    condition: .when(platforms: [.macOS])),
                .product(
                    name: "SparkleUpdateKit", package: "swiftkit-sparkle",
                    condition: .when(traits: ["SelfUpdating"])),
                .product(
                    name: "TelemetryKit", package: "swiftkit",
                    condition: .when(traits: ["Telemetry"])),
            ]
        ),
        .testTarget(name: "AppScaffoldKitTests", dependencies: ["AppScaffoldKit"]),
    ]
)
