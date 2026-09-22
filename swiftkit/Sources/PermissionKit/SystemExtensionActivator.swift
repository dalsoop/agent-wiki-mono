import Foundation
import SystemExtensions
import os

/// System Extension 활성화 요청의 **공용 정본**(OSSystemExtensionRequest).
///
/// 앱마다 `OSSystemExtensionRequest` 델리게이트를 손수 구현하면, 재설치·재빌드 때
/// 교체 정책(`ReplacementAction`)이 제각각이라 낡은 등록이 남아 권한/승인 매니저에
/// **같은 확장이 둘로 뜬다**. 이 타입은 활성화 요청을 한 곳에서 처리하고 기존 확장을
/// 항상 `.replace` 로 교체 → 재설치해도 중복 등록이 생기지 않는다. `SystemExtension`
/// 이 status/openSettings 에 더해 activate 까지 소유하게 하는 짝.
///
/// 델리게이트 콜백은 `.main` 큐로 받으므로 클래스 자체는 액터 격리하지 않는다
/// (프로토콜이 nonisolated 를 요구).
/// 활성화(교체) 요청의 종착 결과. `requestNeedsUserApproval` 은 종착이 아니라 진행
/// 상태라서 여기 없다 — 승인 대기는 `onNeedsApproval` 로 중간에 알린다.
public enum ActivationResult: Sendable, Equatable {
    case completed
    case willCompleteAfterReboot
}

public final class SystemExtensionActivator: NSObject, OSSystemExtensionRequestDelegate, @unchecked Sendable {
    public let extensionIdentifier: String
    private let diag: (@Sendable (String) -> Void)?
    private let log = Logger(subsystem: "PermissionKit", category: "sysext")

    /// 승인 대기 시작을 알리는 중간 훅(요청은 아직 끝나지 않는다). 배너 갱신용.
    public var onNeedsApproval: (@Sendable () -> Void)?

    /// 진행 중 요청에 도착한 후속 호출자들은 **합쳐진다** — 같은 확장의 활성화를 원하는
    /// 모든 호출자는 같은 결과를 받고, OSSystemExtensionManager 에 중복 요청도 쌓이지
    /// 않는다. 이전엔 completion 을 덮어써 첫 호출자의 결과를 잃었다(2026-08-25 검수).
    private var completions: [(Result<ActivationResult, Error>) -> Void] = []
    private var inFlight = false

    /// - Parameter diag: 진단 로그 싱크(옵션). os_log default 레벨은 헤드리스로 안 보이므로,
    ///   앱이 파일 로거를 주입하면 재설치·활성화 흐름을 파일로 추적할 수 있다.
    public init(extensionIdentifier: String, diag: (@Sendable (String) -> Void)? = nil) {
        self.extensionIdentifier = extensionIdentifier
        self.diag = diag
    }

    private func emit(_ s: String) {
        diag?(s)
        log.log("\(s, privacy: .public)")
    }

    /// 활성화 요청. 이미 같은 버전이 활성화돼 있으면 즉시 성공에 가깝게 완료된다.
    public func activate(_ completion: @escaping (Result<ActivationResult, Error>) -> Void) {
        completions.append(completion)
        guard !inFlight else { return }
        inFlight = true
        emit("activate() — submitRequest \(extensionIdentifier)")
        let req = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionIdentifier, queue: .main)
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }

    private func finish(_ result: Result<ActivationResult, Error>) {
        inFlight = false
        let waiting = completions
        completions = []
        waiting.forEach { $0(result) }
    }

    // MARK: OSSystemExtensionRequestDelegate

    public func request(_ request: OSSystemExtensionRequest,
                        actionForReplacingExtension existing: OSSystemExtensionProperties,
                        withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        // 재설치/재빌드: 기존 등록을 항상 교체 → 중복 sysext 등록 방지.
        .replace
    }

    public func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        emit("requestNeedsUserApproval — System Settings 승인 필요")
        onNeedsApproval?()
    }

    public func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        emit("didFinishWithResult: \(result.rawValue)")
        switch result {
        case .willCompleteAfterReboot: finish(.success(.willCompleteAfterReboot))
        default: finish(.success(.completed))
        }
    }

    public func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let ns = error as NSError
        emit("didFailWithError: \(error.localizedDescription) [\(ns.domain) \(ns.code)]")
        finish(.failure(error))
    }
}

extension SystemExtension {
    /// 이 확장의 활성화를 요청한다. 반환된 activator 를 호출부가 붙들고 있어야
    /// 델리게이트 콜백이 유지된다(요청이 끝날 때까지).
    public func makeActivator(diag: (@Sendable (String) -> Void)? = nil) -> SystemExtensionActivator {
        SystemExtensionActivator(extensionIdentifier: bundleID, diag: diag)
    }
}
