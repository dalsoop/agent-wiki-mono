import Foundation

extension AgentCLICommand {
    /// 킷이 소유하는 동사. `handle` / `runSync` 의 입구와 같다.
    public static let railVerbs: Set<String> = ["agent", "skill", "chat", "status"]

    /// 동기 CLI 엔트리. 킷 동사면 exit code, 아니면 `nil` 이라 앱 `switch` 가 이어진다.
    public func runSync(_ args: [String]) -> Int32? {
        let result = HelpersDomainCLI.runBlocking { [self] in
            await handle(args)
        }
        if case .handled(let code) = result {
            return code
        }
        return nil
    }
}
