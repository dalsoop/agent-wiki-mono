import Foundation

/// 자격증명이 저장돼 실제로 쓰이는 곳 하나.
///
/// 회전이 위험한 이유는 전부 여기서 나온다 — 소비처를 모르고 자격증명을 바꾸면
/// 조용히 깨진다. 그래서 이 타입은 **교체 방법과 검증 방법을 함께** 들고 다닌다.
public struct CredentialConsumer: Sendable, Identifiable, Equatable {
    public enum Kind: String, Sendable, Codable {
        /// 설정 파일(값이 파일 안에 문자열로 있음).
        case file
        /// k8s Secret 등 외부 저장소.
        case secretStore
        /// CI/CD 변수.
        case ciVariable
        /// 사람이 손으로 넣어야 하는 곳(브라우저 세션·외부 SaaS 등).
        case manual
    }

    public let id: String
    public let kind: Kind
    /// 사람이 읽을 위치 설명. 예: `argocd/crawler-mono-repo:password`, `~/.config/glab-cli/config.yml`
    public let location: String
    /// 이 소비처가 값을 몇 군데에 들고 있나(파일 내 출현 횟수 등).
    public let occurrences: Int

    public init(id: String, kind: Kind, location: String, occurrences: Int = 1) {
        self.id = id
        self.kind = kind
        self.location = location
        self.occurrences = occurrences
    }

    /// 사람 손이 필요한가 — 자동 교체가 불가능한 소비처.
    public var requiresManualStep: Bool { kind == .manual }
}

public enum RotationError: Error, LocalizedError, Equatable, Sendable {
    case noConsumersFound
    case scannersFailed([String])
    case manualConsumersPending([String])
    case verificationFailed(String)
    case outOfOrder(expected: String, got: String)

    public var errorDescription: String? {
        switch self {
        case .noConsumersFound:
            "소비처를 하나도 찾지 못했다. 자격증명이 어디서 쓰이는지 모르는 채로 회전하면 조용히 깨진다 — 먼저 찾아라."
        case let .scannersFailed(details):
            "못 훑은 자리가 있다: \(details.joined(separator: " / ")). 안 본 자리가 있는 채로 "
                + "회전하면 그 소비처가 조용히 죽는다 — 원인을 먼저 없애라."
        case let .manualConsumersPending(locations):
            "사람이 직접 바꿔야 하는 소비처가 남았다: \(locations.joined(separator: ", "))"
        case let .verificationFailed(detail):
            "새 자격증명 검증 실패 — 구 자격증명을 폐기하지 않았다. \(detail)"
        case let .outOfOrder(expected, got):
            "회전 단계 순서 위반: \(expected) 다음이어야 하는데 \(got) 를 시도했다."
        }
    }
}

/// 회전 절차의 단계. **순서를 건너뛸 수 없다.**
///
/// 이 순서는 실제 사고에서 나왔다(2026-07-27): ArgoCD 매니페스트의 repoURL 만 먼저
/// 바꿨더니 크리덴셜이 URL 정확일치라 전 App 이 인증 거부로 죽었다. 새 자격증명을
/// **먼저 등록**하고 소비처를 옮긴 뒤, **검증이 끝나야** 구 자격증명을 폐기한다.
public enum RotationStage: Int, Sendable, Codable, Comparable, CaseIterable {
    /// 소비처를 모두 찾았다.
    case consumersDiscovered = 0
    /// 새 자격증명을 발급했다(구 자격증명은 아직 살아 있다).
    case newIssued = 1
    /// 소비처를 새 값으로 모두 교체했다.
    case consumersUpdated = 2
    /// 새 값이 실제로 동작함을 확인했다.
    case verified = 3
    /// 구 자격증명을 폐기했다.
    case oldRevoked = 4

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .consumersDiscovered: "소비처 파악"
        case .newIssued: "새 자격증명 발급"
        case .consumersUpdated: "소비처 교체"
        case .verified: "동작 검증"
        case .oldRevoked: "구 자격증명 폐기"
        }
    }
}

/// 회전 진행 상태. 값 타입이라 UI 가 그대로 그릴 수 있고,
/// 중단됐을 때 어디까지 갔는지가 남는다(중단 자체가 위험하므로).
public struct RotationProgress: Sendable, Equatable {
    public let target: ManagedCredential
    public private(set) var stage: RotationStage
    public private(set) var consumers: [CredentialConsumer]
    public private(set) var updated: Set<String>
    public private(set) var newCredentialID: CredentialID?

    public init(target: ManagedCredential, consumers: [CredentialConsumer]) {
        self.target = target
        self.consumers = consumers
        self.stage = .consumersDiscovered
        self.updated = []
        self.newCredentialID = nil
    }

    /// 아직 교체되지 않은 소비처.
    public var pending: [CredentialConsumer] {
        consumers.filter { !updated.contains($0.id) }
    }

    /// 사람 손이 필요한데 아직 안 된 것.
    public var pendingManual: [CredentialConsumer] {
        pending.filter(\.requiresManualStep)
    }

    public var isComplete: Bool { stage == .oldRevoked }

    // MARK: - 전이 (순서 강제)

    /// 앱 UI 의 단계별 구동을 위해 public — 발급 API 가 없는 제공자(R2 대시보드 등)는
    /// 사람이 발급·폐기하고 앱이 순서만 강제하는 변형 회전이 정상 경로다.
    public mutating func advance(to next: RotationStage) throws {
        guard next.rawValue == stage.rawValue + 1 else {
            throw RotationError.outOfOrder(expected: stage.label, got: next.label)
        }
        stage = next
    }

    public mutating func recordIssued(_ id: CredentialID) throws {
        try advance(to: .newIssued)
        newCredentialID = id
    }

    /// 소비처 하나 교체 완료를 기록한다. 전부 끝나야 다음 단계로 간다.
    public mutating func markUpdated(_ consumerID: String) {
        updated.insert(consumerID)
    }

    public mutating func finishUpdatingConsumers() throws {
        guard pending.isEmpty else {
            throw RotationError.manualConsumersPending(pending.map(\.location))
        }
        try advance(to: .consumersUpdated)
    }

    public mutating func recordVerified() throws { try advance(to: .verified) }
    public mutating func recordRevoked() throws { try advance(to: .oldRevoked) }
}

// MARK: - 제공자 계약

/// 자격증명 저장소(GitLab·Infisical·…)가 구현하는 최소 계약.
public protocol CredentialProvider: Sendable {
    /// 사람이 읽을 출처 이름(호스트 등).
    var sourceName: String { get }

    func listCredentials() async throws -> [ManagedCredential]

    /// 같은 소유자·스코프로 새 자격증명을 발급한다.
    func issue(like target: ManagedCredential, name: String) async throws -> IssuedCredential

    func revoke(id: CredentialID) async throws

    /// **값 → id 역인식.** 대부분의 API 는 값을 돌려주지 않으므로, 어딘가에서 발견한
    /// 값이 어느 자격증명인지 알아내려면 그 값으로 인증을 시도해 보는 수밖에 없다.
    /// 이게 소비처 탐색의 유일한 확인 수단이다.
    func identify(value: String) async throws -> CredentialID?
}

/// 자격증명 값이 저장돼 있을 만한 곳을 훑는 쪽.
public protocol ConsumerScanner: Sendable {
    /// 스캔해서 발견한 (값, 위치) 쌍을 돌려준다.
    func scan() async throws -> [(value: String, consumer: CredentialConsumer)]
    /// 소비처의 값을 새 값으로 교체한다. `manual` 종류면 false 를 돌려준다.
    func replace(_ consumer: CredentialConsumer, with newValue: String) async throws -> Bool
}

/// 스캐너 하나가 못 돈 사실. "소비처 없음"과 절대 섞이면 안 되는 정보다.
public struct ScannerFailure: Sendable {
    public let scanner: String
    public let error: any Error

    public init(scanner: String, error: any Error) {
        self.scanner = scanner
        self.error = error
    }

    public var description: String {
        "\(scanner): \((error as? LocalizedError)?.errorDescription ?? "\(error)")"
    }
}

// MARK: - 회전 실행

public struct RotationCoordinator: Sendable {
    private let provider: any CredentialProvider
    private let scanners: [any ConsumerScanner]

    public init(provider: any CredentialProvider, scanners: [any ConsumerScanner]) {
        self.provider = provider
        self.scanners = scanners
    }

    /// 1단계. 이 자격증명을 들고 있는 소비처를 찾는다.
    ///
    /// 하나도 못 찾으면 **의도적으로 실패한다** — "못 찾았으니 없나 보다" 로 넘어가는 것이
    /// 정확히 사고가 나는 경로다. 진짜로 소비처가 없다면 회전이 아니라 폐기 대상이다.
    /// 스캐너 하나가 실패해도 나머지 결과는 살린다. 예전에는 첫 실패가 통째로 던져서
    /// 파일 스캔 결과까지 날아갔다 — 사용자에겐 "소비처 없음"과 구분이 안 됐다.
    /// 대신 실패를 모아 두고, **회전으로 넘어가기 전에** 반드시 드러낸다.
    public func discoverConsumers(for target: ManagedCredential) async throws -> RotationProgress {
        let (progress, failures) = try await discoverConsumersAllowingFailures(for: target)
        guard failures.isEmpty else {
            throw RotationError.scannersFailed(failures.map { $0.description })
        }
        return progress
    }

    /// 조회(읽기 전용) 경로용 — 실패한 스캐너를 함께 돌려준다. 회전은 이걸 직접 쓰지
    /// 않는다: 못 본 자리가 있는 채로 구 자격증명을 폐기하면 그게 사고다.
    public func discoverConsumersAllowingFailures(
        for target: ManagedCredential
    ) async throws -> (progress: RotationProgress, failures: [ScannerFailure]) {
        var found: [CredentialConsumer] = []
        var failures: [ScannerFailure] = []
        for scanner in scanners {
            do {
                for (value, consumer) in try await scanner.scan() {
                    if try await provider.identify(value: value) == target.id {
                        found.append(consumer)
                    }
                }
            } catch {
                failures.append(ScannerFailure(scanner: "\(type(of: scanner))", error: error))
            }
        }
        guard !found.isEmpty || !failures.isEmpty else { throw RotationError.noConsumersFound }
        return (RotationProgress(target: target, consumers: found), failures)
    }

    /// 2~5단계를 순서대로 진행한다. 어느 단계에서 실패해도 **구 자격증명은 살아 있다.**
    public func rotate(_ progress: inout RotationProgress,
                       newName: String,
                       verify: @Sendable (IssuedCredential) async -> Bool) async throws {
        // 2) 새 것 발급 — 구 것은 그대로 둔다.
        let issued = try await provider.issue(like: progress.target, name: newName)
        try progress.recordIssued(issued.id)

        // 3) 소비처 교체. 자동 교체가 안 되는 곳은 pending 으로 남는다.
        for consumer in progress.pending where !consumer.requiresManualStep {
            for scanner in scanners {
                if try await scanner.replace(consumer, with: issued.value) {
                    progress.markUpdated(consumer.id)
                    break
                }
            }
        }
        try progress.finishUpdatingConsumers()

        // 4) 검증 — 여기가 통과해야만 폐기로 간다.
        guard await verify(issued) else {
            throw RotationError.verificationFailed(
                "새 자격증명 \(issued.maskedValue) 로 동작 확인 실패")
        }
        try progress.recordVerified()

        // 5) 이제서야 구 자격증명을 폐기한다.
        try await provider.revoke(id: progress.target.id)
        try progress.recordRevoked()
    }
}
