// swift-tools-version: 6.1
import PackageDescription

// Sparkle 2 자동업데이트를 swiftkit 앱들에 한 줄로 붙이는 얇은 래퍼.
//
// swiftkit 본체는 "외부 의존성 0건"을 불변량으로 지킨다(모든 앱이 swiftkit을 끌기 때문에
// 여기에 Sparkle을 넣으면 비사용 앱까지 매 빌드마다 SPM resolve 비용을 지운다). 그래서
// Sparkle은 이 별도 패키지에서만 의존한다. 앱은:
//
//   .package(path: "../../swiftkit-sparkle")
//   .product(name: "SparkleUpdateKit", package: "swiftkit-sparkle")
//
// 로 끌어온 뒤, 진입점에서 `.sparkleUpdates()` 또는 `SparkleUpdaterHost.shared.start()`
// 한 줄로 옵트인한다. UpdateKit(.selfUpdates())을 대체한다.
let package = Package(
    name: "swiftkit-sparkle",
    defaultLocalization: "en",
    // iOS 최소값은 의존하는 swiftkit(AppWindowKit, iOS 18)과 맞춘다 — 선언이 없으면 기본
    // iOS 12 로 잡혀 screenshot-ios 처럼 이 패키지가 그래프에 들어오는 iOS 목적지 빌드가
    // 매니페스트 검증에서 깨진다(SparkleUpdateKit 자체는 iOS 에서 빌드되지 않는다).
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "SparkleUpdateKit", targets: ["SparkleUpdateKit"]),
    ],
    dependencies: [
        .package(path: "../swiftkit"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "SparkleUpdateKit",
            dependencies: [
                .product(name: "AppWindowKit", package: "swiftkit"),
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "SettingsUIKit", package: "swiftkit"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SparkleUpdateKitTests",
            dependencies: ["SparkleUpdateKit"]
        ),
    ]
)
