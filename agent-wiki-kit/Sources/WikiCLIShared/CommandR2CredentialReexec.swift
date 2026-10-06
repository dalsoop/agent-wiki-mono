import Darwin
import Foundation
import KnowledgeBaseWikiCore

// R2 키 Bitwarden 재실행 — 판정은 `LawR2BitwardenReexec.decide`(Core, 순수), 여기서는 `execv` 만 한다.
// 근거: docs/security.md "R2 와 세션", 결정 0009. 관례: swift-app-mono dns-zone-manager `credential source`.
// 값은 `vaultwarden-client item field exec … --env` 가 하위 프로세스 환경에만 넣는다. 이 함수는 값을 보지 않는다.

/// R2 키가 꼭 필요한 명령이면, 키체인에 값이 없고 출처가 Bitwarden 일 때 자신을 다시 실행한다(돌아오지 않음).
/// 그 밖에는 바로 돌아온다. CLI 진입점이 명령 분기 전에 부른다.
/// - Parameter command: 선두 `--as`·`--world` 를 뗀 인자(명령부터).
public func reexecForLawR2CredentialsIfNeeded(command: [String], file: BoundLedgerFile) {
    let decision = LawR2BitwardenReexec.decide(
        command: command, originalArguments: Array(CommandLine.arguments.dropFirst()), file: file,
        keychain: LawKeychainCredentialProvider(), handoff: .current,
        executable: Bundle.main.executablePath, locate: { LawR2BitwardenReexec.locate($0) })
    switch decision {
    case .proceed:
        return
    case .failure(let message):
        fail(message)
    case .reexec(let plan):
        FileHandle.standardError.write(Data("R2 키를 Bitwarden 항목에서 받아 다시 실행합니다\n".utf8))
        setenv(LawR2EnvHandoff.markerVariable, LawR2EnvHandoff.markerValue, 1)
        // execv 는 C 배열을 요구한다. 각 인자를 strdup 해 수명을 프로세스 이미지 교체까지 유지한다.
        var cArguments: [UnsafeMutablePointer<CChar>?] = plan.argv.map { strdup($0) } + [nil]
        execv(plan.program, &cArguments)
        // execv 는 성공하면 돌아오지 않는다.
        let reason = String(cString: strerror(errno))
        unsetenv(LawR2EnvHandoff.markerVariable)
        fail("\(plan.program) 실행 실패: \(reason)")
    }
}
