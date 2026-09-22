import Foundation
import Crypto

// MARK: - 감각-운동 도형 블록 및 소켓 모델
// Piaget (1952) 비언어적 구조 감각운동기 및 Oudeyer et al. (2007) 내재적 호기심 엔진

public enum BlockShape: String, Sendable, Codable, CaseIterable, Equatable {
    case deterministicFixed = "DETERMINISTIC_FIXED"       // 규격 고정 블록 (하드웨어/SSOT 메트릭)
    case oscillatingRandom = "OSCILLATING_RANDOM"         // 진동/불안정 블록 (Double.random 등)
    case unmanagedShellScript = "UNMANAGED_SHELL_SCRIPT" // 규격 외 돌출 블록 (sh deploy.sh)
    case nativeSwiftCli = "NATIVE_SWIFT_CLI"             // 정식 Swift CLI 블록 (app-build-manager)
    case unsafeUnwrappedTry = "UNSAFE_UNWRAPPED_TRY"     // 삐죽 튀어나온 블록 (try!)
    case guardedCatchTry = "GUARDED_CATCH_TRY"           // 홈에 맞물리는 블록 (do { try } catch)
    case unknownNovelShape = "UNKNOWN_NOVEL_SHAPE"       // 미지의 낯선 블록 (호기심 유발)
}

public struct InvariantSocket: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let requiredShape: BlockShape
    public let baselineHash: String
    public let targetFilePath: String?

    public init(
        id: String,
        name: String,
        requiredShape: BlockShape,
        baselineHash: String,
        targetFilePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.requiredShape = requiredShape
        self.baselineHash = baselineHash
        self.targetFilePath = targetFilePath
    }
}

public struct TokenBlock: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let shape: BlockShape
    public let payloadData: Data

    public var payloadHash: String {
        let digest = SHA256.hash(data: payloadData)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public init(id: String = UUID().uuidString, shape: BlockShape, payloadData: Data) {
        self.id = id
        self.shape = shape
        self.payloadData = payloadData
    }

    public init(id: String = UUID().uuidString, shape: BlockShape, payloadBytes: Data) {
        self.id = id
        self.shape = shape
        self.payloadData = payloadBytes
    }

    public init(id: String = UUID().uuidString, shape: BlockShape, payloadString: String) {
        self.id = id
        self.shape = shape
        self.payloadData = Data(payloadString.utf8)
    }
}

public enum SensorimotorFitResult: Sendable, Equatable {
    case clickedIn(
        socketId: String,
        restoredHash: String,
        reversibilityScore: Double,
        deltaH: Double,
        valenceBoost: Double
    )
    case collidedAndRejected(
        socketId: String,
        attemptedShape: BlockShape,
        painValence: Double,
        revertedToBaselineHash: String
    )

    public var isSuccess: Bool {
        switch self {
        case .clickedIn:
            return true
        case .collidedAndRejected:
            return false
        }
    }

    public var revertedHash: String? {
        switch self {
        case .clickedIn(_, let restoredHash, _, _, _):
            return restoredHash
        case .collidedAndRejected(_, _, _, let revertedToBaselineHash):
            return revertedToBaselineHash
        }
    }
}

public final class SensorimotorShapeEngine: Sendable {
    public init() {}

    /// 블록과 소켓 간의 형상 및 체크섬 일치 여부 실측 검증
    public func verifyFit(block: TokenBlock, into socket: InvariantSocket) -> Bool {
        guard block.shape == socket.requiredShape else {
            return false
        }
        return block.payloadHash.caseInsensitiveCompare(socket.baselineHash) == .orderedSame
    }

    /// 블록을 소켓에 맞추어보고 물리적 피팅 결과 산출
    public func evaluateFit(
        block: TokenBlock,
        into socket: InvariantSocket
    ) -> SensorimotorFitResult {
        guard block.shape == socket.requiredShape else {
            return .collidedAndRejected(
                socketId: socket.id,
                attemptedShape: block.shape,
                painValence: -0.85,
                revertedToBaselineHash: socket.baselineHash
            )
        }

        return .clickedIn(
            socketId: socket.id,
            restoredHash: block.payloadHash,
            reversibilityScore: 1.0,
            deltaH: 0.0,
            valenceBoost: 0.85
        )
    }

    /// 신기성(Novelty) 호기심 점수 산출
    public func curiosityNoveltyScore(for shape: BlockShape) -> Double {
        switch shape {
        case .unknownNovelShape:
            return 0.75
        case .oscillatingRandom, .unmanagedShellScript, .unsafeUnwrappedTry:
            return 0.55
        case .deterministicFixed, .nativeSwiftCli, .guardedCatchTry:
            return 0.20
        }
    }
}
