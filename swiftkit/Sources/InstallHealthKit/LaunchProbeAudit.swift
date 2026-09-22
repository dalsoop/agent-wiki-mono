import Foundation

/// 설치 앱 바이너리를 잠깐 실행해 본 raw 결과. 이 값 자체는 판정이 아니다 —
/// `LaunchProbeAudit` 가 `HealthIssue` 로 바꾼다. 규칙은 이 타입 안에 있지 않다.
public struct LaunchProbe: Equatable, Sendable {
    public let bundleID: String
    public let name: String
    public let path: String
    /// 이미 떠 있거나 실행파일이 없어 스킵했으면 true. 판정 대상이 아니다.
    public let skipped: Bool
    /// 타임아웃 전에 프로세스가 종료됐는가. true 면 즉시 죽은 것이다.
    public let exitedEarly: Bool
    public let exitCode: Int32?
    /// 캡처한 stderr 앞부분.
    public let stderr: String

    public init(
        bundleID: String,
        name: String,
        path: String,
        skipped: Bool = false,
        exitedEarly: Bool = false,
        exitCode: Int32? = nil,
        stderr: String = ""
    ) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
        self.skipped = skipped
        self.exitedEarly = exitedEarly
        self.exitCode = exitCode
        self.stderr = stderr
    }
}

/// 설치 앱 launch-probe 결과의 판정 규칙.
///
/// 크래시 로그(과거 흔적)에 의존하는 기존 탐지와 달리, **실제로 바이너리를 한 번 돌려 본
/// 결과**에서 "켜자마자 죽는" 결함을 잡는다. 임베드 누락 결함은 `.build` 에선 돌아가고
/// `/Applications` 설치본에서만 죽으므로, 이 probe 가 아니면 ship 직후에 안 보인다.
public struct LaunchProbeAudit: Sendable {
    public init() {}

    public func audit(_ probes: [LaunchProbe]) -> [HealthIssue] {
        probes
            // rc=0 으로 조용히 일찍 끝난 건 크래시가 아니다 — 단일 인스턴스 가드가 이미 떠 있는
            // 인스턴스를 발견하고 정상 종료한 경우가 많다. exit≠0 이거나 stderr 가 있을 때만 본다.
            .filter { !$0.skipped && $0.exitedEarly && ($0.exitCode.map { $0 != 0 } ?? true || !$0.stderr.isEmpty) }
            .compactMap { issue(for: $0) }
            .sorted { $0.subject < $1.subject }
    }

    /// 알려진 치명 패턴 하나를 `HealthIssue` 로 바꾼다. 매칭 안 되면 nil(잡음 회피).
    private func issue(for probe: LaunchProbe) -> HealthIssue? {
        let err = probe.stderr

        // SPM 리소스 번들 미복사 — 예: KeyboardShortcuts/resource_bundle_accessor.swift:
        //   Fatal error: could not load resource bundle: from .../Foo_Foo.bundle ...
        if let bundle = firstMatch(in: err, pattern: #"could not load resource bundle: from [^\n]*?([^/\s]+\.bundle)"#) {
            return HealthIssue(
                kind: .fatalLaunchCrash,
                severity: .error,
                subject: probe.bundleID,
                detail: "\(probe.name) 실행 즉시 fatal — SPM 리소스 번들이 .app 에 복사되지 않음:\n    \(bundle)",
                remedy: "make-app.sh(또는 install-app.sh)에서 \(bundle) 을 Contents/Resources/ 로 복사하도록 수정 후 재빌드·재설치."
            )
        }
        if err.contains("could not load resource bundle") {
            return HealthIssue(
                kind: .fatalLaunchCrash,
                severity: .error,
                subject: probe.bundleID,
                detail: "\(probe.name) 실행 즉시 fatal — SPM 리소스 번들 로드 실패:\n    \(firstLine(of: err))",
                remedy: "make-app.sh(또는 install-app.sh)에서 SPM 리소스 번들(*.bundle)을 Contents/Resources/ 로 복사하도록 수정 후 재빌드·재설치."
            )
        }

        // 임베드 프레임워크 누락 — 예: dyld: Library not loaded: @rpath/Sparkle.framework/...
        if let framework = firstMatch(in: err, pattern: #"Library not loaded: [^\n]*?([^/\s]+\.framework)"#) {
            return HealthIssue(
                kind: .fatalLaunchCrash,
                severity: .error,
                subject: probe.bundleID,
                detail: "\(probe.name) 실행 즉시 fatal — \(framework) 가 .app 에 임베드되지 않음(dyld 로드 실패).",
                remedy: "make-app.sh(또는 install-app.sh)에서 \(framework) 를 Contents/Frameworks/ 로 복사(copy-frameworks)하도록 수정 후 재빌드·재설치."
            )
        }

        // 그 외 dyld / Swift fatal — 분류는 못 하지만 "켜면 죽는다" 사실은 보고한다.
        if err.contains("dyld") || err.contains("Fatal error:") {
            return HealthIssue(
                kind: .fatalLaunchCrash,
                severity: .error,
                subject: probe.bundleID,
                detail: "\(probe.name) 실행 즉시 fatal:\n    \(firstLine(of: err))",
                remedy: "stderr 전문을 보고 원인(SPM 리소스·프레임워크 임베드·엔타이틀먼트 등)을 확인 후 make-app.sh·재설치."
            )
        }
        return nil
    }

    // MARK: - helpers

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range),
              m.numberOfRanges > 1,
              let capture = Range(m.range(at: 1), in: text)
        else { return nil }
        return String(text[capture])
    }

    private func firstLine(of text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
    }
}
