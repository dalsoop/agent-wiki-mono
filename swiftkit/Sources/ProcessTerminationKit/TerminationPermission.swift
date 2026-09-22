import Darwin
import Foundation

/// 프로세스 종료 권한 검사기
public enum TerminationPermission {
    public enum Capability: Equatable, Sendable {
        /// 동일 UID 프로세스로 일반 권한으로 종료 가능
        case standard
        /// root/타 사용자 프로세스로 관리자 권한(Privileged Escalation) 필요
        case requiresPrivilege
        /// 프로세스가 이미 존재하지 않음
        case notFound
    }

    /// 대상 프로세스를 현재 권한으로 종료(시그널 전송)할 수 있는지 사전 검사
    public static func check(pid: pid_t) -> Capability {
        guard pid > 0 else { return .notFound }

        // kill(pid, 0)은 실제로 시그널을 보내지 않고 에러 검사만 수행함
        let res = kill(pid, 0)
        if res == 0 {
            return .standard
        }

        switch errno {
        case EPERM:
            return .requiresPrivilege
        case ESRCH:
            return .notFound
        default:
            return .requiresPrivilege
        }
    }
}
