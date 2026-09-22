import Foundation
import StateMirrorKit

// MARK: - Errors

public enum CertificateClientError: Error, LocalizedError {
    case hubNotRunning
    case noCertificateSelected
    case certificateExpired(subject: String, since: Date)
    case noVaultCardLinked
    case stateMalformed(String)

    public var errorDescription: String? {
        switch self {
        case .hubNotRunning:
            return "joint-certificate-manager 가 실행 중이지 않거나 상태를 발행하지 않았습니다."
        case .noCertificateSelected:
            return "활성 인증서가 선택되지 않았습니다. joint-certificate-manager use <id> 를 실행하세요."
        case .certificateExpired(let subject, let since):
            return "인증서가 만료됐습니다: \(subject) (만료: \(since))"
        case .noVaultCardLinked:
            return "인증서 비밀번호 vault 카드가 연결되지 않았습니다. joint-certificate-manager vault link 를 실행하세요."
        case .stateMalformed(let detail):
            return "StateMirror 상태가 올바르지 않습니다: \(detail)"
        }
    }
}

// MARK: - Client

/// 소비자 앱이 공동인증서에 접근하는 **유일한 진입점**.
///
/// CertificateKit 을 import 하고 CertificateClient() 로 인스턴스를 만든 뒤,
/// activeRef() 로 CertificateRef 를, password() 로 CertificatePasswordRef 를 얻는다.
///
/// 내부적으로 joint-certificate-manager 의 StateMirror 상태를 읽는다.
/// 소비자 앱은 NPKI 경로, 발급기관, DER 파일을 직접 몰라도 된다.
public struct CertificateClient: Sendable {
    private let appId: String
    private let isoDecoder: JSONDecoder

    public init(appId: String = CertificateHubState.mirrorAppId) {
        self.appId = appId
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.isoDecoder = dec
    }

    // MARK: - Public API

    /// joint-certificate-manager 가 지정한 활성 인증서 참조를 반환한다.
    /// - Throws: `CertificateClientError` (허브 미실행·미선택·만료 등)
    public func activeRef() throws -> CertificateRef {
        let state = try readState()
        guard let ref = state.toCertificateRef() else {
            throw CertificateClientError.noCertificateSelected
        }
        if ref.isExpired {
            throw CertificateClientError.certificateExpired(subject: ref.subject, since: ref.validUntil)
        }
        return ref
    }

    /// 활성 인증서의 vault 비밀번호 참조를 반환한다.
    /// - Throws: `CertificateClientError.noVaultCardLinked` — 카드 미연결
    public func password() throws -> CertificatePasswordRef {
        let state = try readState()
        guard let pw = state.toPasswordRef() else {
            throw CertificateClientError.noVaultCardLinked
        }
        return pw
    }

    /// 활성 인증서가 없거나 만료됐을 때 true.
    /// 사용자에게 joint-certificate-manager 안내를 띄워야 하는지 판단할 때 사용.
    public func needsAttention() -> Bool {
        do {
            guard let ref = try readState().toCertificateRef() else { return true }
            return ref.isExpired
        } catch {
            // 상태를 읽지 못하면(파일 부재·깨짐) 소비자 앱에 주의 안내가 맞다 — true 가 정상 경로다.
            if (error as NSError).code != NSFileReadUnknownError {
                FileHandle.standardError.write("CertificateClient readState failed: \(error.localizedDescription)\n".data(using: .utf8)!)
            }
            return true
        }
    }

    /// 원시 허브 상태 (고급 사용, 일반적으로 불필요).
    public func rawState() throws -> CertificateHubState {
        try readState()
    }

    // MARK: - Internal

    private func readState() throws -> CertificateHubState {
        let statePath = StateMirror.path(app: appId)
        guard FileManager.default.fileExists(atPath: statePath) else {
            throw CertificateClientError.hubNotRunning
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: statePath))
            // StateMirrorEnvelope<CertificateHubState> 형식
            let envelope = try isoDecoder.decode(
                StateMirrorEnvelope<CertificateHubState>.self,
                from: data
            )
            return envelope.state
        } catch let e as CertificateClientError {
            throw e
        } catch {
            throw CertificateClientError.stateMalformed(error.localizedDescription)
        }
    }
}
