import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// **사설 스토어 / 사이드로드** 권한 원장 — 서명 라이선스 (`SignedLicenseCodec` / sl1).
///
/// F-Droid · 기업 배포 · 오프라인 키 파일. `LicenseKit.SignedLicenseCodec` 으로 검증한다.
///
/// ## 채택
/// ```swift
/// ContentView().privateLicenseManaged()
/// // 또는 .entitlementManaged(channel: .privateStore)
/// ```
///
/// ## Info.plist
/// - `PrivateLicensePublicKey` : base64url Ed25519 공개키 (**설정되면 강제 검증**)
/// - `SignedLicensePath` : 라이선스 토큰 파일 경로 (선택)
/// - `PrivateLicenseProductID` : 없으면 `CFBundleIdentifier`
///
/// ## 토큰 탐색 순서
/// 1. env `GUJO_SIGNED_LICENSE` (토큰 원문)
/// 2. env `GUJO_SIGNED_LICENSE_PATH` 또는 plist `SignedLicensePath` 파일
/// 3. `~/Library/Application Support/<bundleId>/license.sl1`
///
/// 공개키가 없으면 **fail-open**. 공개키만 있고 유효 토큰이 없으면 `notEntitled`.
public enum PrivateLicenseManaged {
    public enum Status: String, Sendable, Equatable {
        case available
        case notEntitled
        case unavailable
    }

    private static let cacheKey = "gujo.private-license.lastKnownStatus"

    public static var lastKnown: Status? {
        UserDefaults.standard.string(forKey: cacheKey).flatMap { Status(rawValue: $0) }
    }

    public static func publicKey(from bundle: Bundle = .main) -> String? {
        if let key = bundle.object(forInfoDictionaryKey: "PrivateLicensePublicKey") as? String,
           !key.isEmpty {
            return key
        }
        if let env = ProcessInfo.processInfo.environment["GUJO_PRIVATE_LICENSE_PUBLIC_KEY"],
           !env.isEmpty {
            return env
        }
        return nil
    }

    public static func productIdentifier(from bundle: Bundle = .main) -> String {
        if let id = bundle.object(forInfoDictionaryKey: "PrivateLicenseProductID") as? String,
           !id.isEmpty {
            return id
        }
        return bundle.bundleIdentifier ?? "unknown.product"
    }

    /// 공개키가 있으면 검증 모드.
    public static func isConfigured(bundle: Bundle = .main) -> Bool {
        publicKey(from: bundle) != nil
    }

    /// 토큰 문자열 로드 (없으면 nil).
    public static func loadToken(bundle: Bundle = .main) -> String? {
        if let env = ProcessInfo.processInfo.environment["GUJO_SIGNED_LICENSE"], !env.isEmpty {
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let pathCandidates: [String] = {
            var paths: [String] = []
            if let p = ProcessInfo.processInfo.environment["GUJO_SIGNED_LICENSE_PATH"], !p.isEmpty {
                paths.append(p)
            }
            if let p = bundle.object(forInfoDictionaryKey: "SignedLicensePath") as? String, !p.isEmpty {
                paths.append((p as NSString).expandingTildeInPath)
            }
            let bid = bundle.bundleIdentifier ?? "app"
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            if let support {
                paths.append(support.appendingPathComponent(bid).appendingPathComponent("license.sl1").path)
            }
            return paths
        }()
        for path in pathCandidates {
            if let raw = try? String(contentsOfFile: path, encoding: .utf8) {
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
        }
        return nil
    }

    /// 서명 라이선스가 유효한가.
    public static func hasEntitlement(bundle: Bundle = .main) async -> Bool {
        guard let pub = publicKey(from: bundle) else { return true } // fail-open
        guard let token = loadToken(bundle: bundle) else { return false }
        let product = productIdentifier(from: bundle)
        do {
            _ = try SignedLicenseCodec.verify(
                token, publicKey: pub, expectedProductIdentifier: product, now: Date()
            )
            return true
        } catch {
            return false
        }
    }

    public static func status(bundle: Bundle = .main) async -> Status {
        guard isConfigured(bundle: bundle) else {
            return remember(.available)
        }
        guard loadToken(bundle: bundle) != nil else {
            return remember(.notEntitled)
        }
        let ok = await hasEntitlement(bundle: bundle)
        // 토큰은 있는데 검증 실패(키 불일치·만료) → notEntitled / 키 형식 오류는 unavailable 에 가깝지만
        // 사용자 메시지 단순화를 위해 notEntitled 로 합친다.
        return remember(ok ? .available : .notEntitled)
    }

    private static func remember(_ s: Status) -> Status {
        UserDefaults.standard.set(s.rawValue, forKey: cacheKey)
        return s
    }
}

#if canImport(SwiftUI)
extension View {
    @MainActor
    public func privateLicenseManaged() -> some View {
        PrivateLicenseManagedGateView { self }
    }
}

@MainActor
private struct PrivateLicenseManagedGateView<Content: View>: View {
    let content: Content
    @State private var status: PrivateLicenseManaged.Status = .available

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group {
            if status == .available {
                content
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(status == .notEntitled
                         ? "유효한 서명 라이선스가 없습니다. 배포자에게 키를 요청하세요."
                         : "라이선스를 확인할 수 없습니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("사설 스토어 · 서명 라이선스")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(24)
            }
        }
        .task {
            status = await PrivateLicenseManaged.status()
        }
    }
}
#endif
