import Foundation

/// 스캐폴드 출생 기본값. 앱 고유 불변식으로 바꾸기 전에는 doctor 가 실패한다.
public struct UnimplementedDomainDoctorProvider: DoctorProvider {
    public let id = "domain-unimplemented"
    private let subject: String

    public init(subject: String) {
        self.subject = subject
    }

    public func run() async -> [DoctorFinding] {
        [DoctorFinding(
            category: .runtime,
            severity: .fail,
            body: .init(
                subject: subject,
                title: "도메인 doctor 가 아직 없다",
                detail: "HelpersDomainCLI.doctor extra 에 이 앱 불변식을 꽂지 않았다",
                remedy: "공용 JSON·LaunchAgent·번들 provider 또는 앱 Core provider 로 교체한다"
            ),
            source: id
        )]
    }
}
