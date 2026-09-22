// swift-tools-version: 6.1
import PackageDescription

// CitationLedgerKit — knowledge-base-wiki 와 monorepo-git-forge 가 공유하는
// append-only content-addressed 원장의 **코어 메커니즘**(해시·주소·시간포맷·검증).
// 두 앱의 객체(LedgerObject·ForgeObject)는 필드 집합이 달라 하나로 합치지 않고,
// 이 프로토콜에 conform 해 공통 유틸을 재사용한다.
//
// swiftkit(macOS/CryptoKit) 이 아니라 **독립 크로스플랫폼 패키지**다 — forge 서버가
// Linux 라 swift-crypto 를 써야 하기 때문(pulsekit·sshkit 처럼 sibling 로 분리).
let package = Package(
    name: "citationledgerkit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CitationLedgerKit", targets: ["CitationLedgerKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "CitationLedgerKit",
            dependencies: [.product(name: "Crypto", package: "swift-crypto")]),
        .testTarget(
            name: "CitationLedgerKitTests", dependencies: ["CitationLedgerKit"]),
    ]
)
