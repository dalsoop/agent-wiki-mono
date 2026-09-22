import Foundation
import StateRootKit

/// 프로세스 또는 도구 실행 시 룸 샌드박스 내부 진입을 강제(Mandatory Enforcement)하는 게이트.
public enum SandboxGate {
    public enum GateError: Error, LocalizedError, Equatable {
        case roomSandboxRequired(String)

        public var errorDescription: String? {
            switch self {
            case .roomSandboxRequired(let reason):
                return "🚨 [ROOM_SANDBOX_REQUIRED] 룸 샌드박스 진입 필수: \(reason)"
            }
        }
    }

    /// 현재 프로세스가 룸 샌드박스 내부에서 격리 실행 중인지 확인하고, 아니면 에러를 던진다.
    @discardableResult
    public static func check(
        operationName: String = "작업",
        environment: [String: String] = ProcessInfo.processInfo.environment,
        strict: Bool = true
    ) throws -> Bool {
        if StateRootKit.isInsideRoomSandbox(environment) || StateRootKit.isRunningUnderTest(environment) {
            return true
        }

        if strict || environment["STRICT_ROOM_ENFORCEMENT"] == "1" {
            throw GateError.roomSandboxRequired(
                "베어메탈 직접 실행이 금지되어 있습니다. 'agent-seat-manager room exec --tenant <slug> -- <명령어>'를 통해 룸 샌드박스 내부에서 실행하세요. (\(operationName))"
            )
        }
        return false
    }

    /// 룸 샌드박스 밖에서 실행 시 즉시 샌드박스를 자동 생성(Auto-Wrap)하여 감싸서 실행한다.
    public static func autoWrapOrRun<T: Sendable>(
        tenant: String,
        operationName: String = "작업",
        environment: [String: String] = ProcessInfo.processInfo.environment,
        _ block: @Sendable (SandboxContext) throws -> T
    ) throws -> T {
        if StateRootKit.isInsideRoomSandbox(environment) {
            let roomID = environment["SANDBOX_ROOM_ID"] ?? "current-room"
            let hostHome = StateRootKit.resolveHost(environment: [:])
            let stateRoot = environment["SWIFT_APP_STATE_ROOT"] ?? hostHome
            let sandboxDir = URL(fileURLWithPath: stateRoot, isDirectory: true)
            let ctx = SandboxContext(
                roomID: roomID,
                tenantSlug: tenant,
                sandboxDirectory: sandboxDir,
                tmpDirectory: sandboxDir.appendingPathComponent("tmp", isDirectory: true),
                readOnlyMasterRoot: SandboxLayout.url(".tenants/\(tenant)", homeDirectory: hostHome)
            )
            return try block(ctx)
        } else {
            // 룸 밖이면 자동으로 일회성 룸을 띄워 안전하게 감싸서 실행 (Auto-Wrap)
            return try SandboxRunner.withOneShotSandbox(tenant: tenant) { ctx in
                try block(ctx)
            }
        }
    }
}
