import Foundation
import StateRootKit
import LocalizationKit

/// 봇 탐지 우회를 위한 fingerprint 프로필.
///
/// 세션 생성 시 프로필을 바인딩하면, CDP evaluate 전에
/// navigator/canvas/webgl override 스크립트가 주입된다.
/// 프로필 내 값은 교차검증돼야 한다 (UA ↔ platform ↔ GPU 일관성).
public struct StealthProfile: Codable, Sendable, Equatable {
    public let id: String
    public let tenant: String?
    public let userAgent: String
    public let platform: String
    public let languages: [String]
    public let timezone: String
    public let screenWidth: Int
    public let screenHeight: Int
    public let colorDepth: Int
    public let hardwareConcurrency: Int
    public let deviceMemory: Int
    public let webglVendor: String
    public let webglRenderer: String
    /// Canvas fingerprint 에 더할 결정적 노이즈 시드.
    public let canvasNoiseSeed: Int

    public init(id: String, tenant: String? = nil, userAgent: String, platform: String = "MacIntel",
                languages: [String] = ["ko-KR", "ko", "en-US", "en"],
                timezone: String = "Asia/Seoul",
                screenWidth: Int = 1920, screenHeight: Int = 1080,
                colorDepth: Int = 24, hardwareConcurrency: Int = 10,
                deviceMemory: Int = 8,
                webglVendor: String = "Apple",
                webglRenderer: String = "Apple M1 Max",
                canvasNoiseSeed: Int = 0) {
        self.id = id
        self.tenant = tenant
        self.userAgent = userAgent
        self.platform = platform
        self.languages = languages
        self.timezone = timezone
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.colorDepth = colorDepth
        self.hardwareConcurrency = hardwareConcurrency
        self.deviceMemory = deviceMemory
        self.webglVendor = webglVendor
        self.webglRenderer = webglRenderer
        self.canvasNoiseSeed = canvasNoiseSeed
    }
}

/// 프로필 교차검증 — UA/platform/GPU 간 모순 탐지.
public enum StealthProfileDoctor {
    public struct Finding: Sendable {
        public let field: String
        public let message: String
    }

    public static func diagnose(_ profile: StealthProfile) -> [Finding] {
        var findings: [Finding] = []
        diagnosePlatform(profile, into: &findings)
        diagnoseHardware(profile, into: &findings)
        return findings
    }

    private static func diagnosePlatform(_ profile: StealthProfile, into findings: inout [Finding]) {
        if profile.userAgent.contains("Windows") && profile.platform == "MacIntel" {
            findings.append(Finding(field: "platform", message: CLILocalization.string("StealthProfile.message")))
        }
        if profile.userAgent.contains("Linux") && profile.platform == "MacIntel" {
            findings.append(Finding(field: "platform", message: CLILocalization.string("StealthProfile.message-2")))
        }
    }

    private static func diagnoseHardware(_ profile: StealthProfile, into findings: inout [Finding]) {
        diagnoseRenderer(profile, into: &findings)
        diagnoseLimits(profile, into: &findings)
    }

    private static func diagnoseRenderer(_ profile: StealthProfile, into findings: inout [Finding]) {
        if profile.webglRenderer.contains("NVIDIA") && profile.userAgent.contains("Mac OS") {
            findings.append(Finding(field: "webglRenderer", message: CLILocalization.string("StealthProfile.message-3")))
        }
    }

    private static func diagnoseLimits(_ profile: StealthProfile, into findings: inout [Finding]) {
        if profile.screenWidth < 800 || profile.screenHeight < 600 {
            findings.append(Finding(field: "screen", message: CLILocalization.string("StealthProfile.message-4")))
        }
        if profile.hardwareConcurrency < 1 || profile.hardwareConcurrency > 128 {
            findings.append(Finding(field: "hardwareConcurrency", message: CLILocalization.string("StealthProfile.message-5")))
        }
    }
}

/// 프로필 저장/로드.
public enum StealthProfileStore {
    static let relativeRoot = ".agent-browser/stealth-profiles"

    static var rootDirectory: URL {
        StateRootKit.url(relativeRoot)
    }

    static func directory(tenant: String?) -> URL {
        guard let tenant = tenant, !tenant.isEmpty else { return rootDirectory }
        return rootDirectory.appendingPathComponent(tenant)
    }

    public static func save(_ profile: StealthProfile) throws {
        let dir = directory(tenant: profile.tenant)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)
        try data.write(to: dir.appendingPathComponent("\(profile.id).json"))
    }

    public static func load(id: String, tenant: String? = nil) throws -> StealthProfile {
        let data = try Data(contentsOf: directory(tenant: tenant).appendingPathComponent("\(id).json"))
        return try JSONDecoder().decode(StealthProfile.self, from: data)
    }

    public static func list(tenant: String? = nil) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory(tenant: tenant).path))?
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) } ?? []
    }

    /// 이 Mac의 실제 값으로 기본 프로필 생성.
    public static func defaultProfile() -> StealthProfile {
        StealthProfile(
            id: "default",
            userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36",
            canvasNoiseSeed: Int.random(in: 1...999999)
        )
    }
}
