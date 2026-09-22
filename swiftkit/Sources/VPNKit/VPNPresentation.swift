import Foundation
import LocalizationKit
import Observation

public enum VPNPresentationLanguage: String, Codable, Sendable {
    case system
    case korean
    case english
}

enum VPNRecoveryCandidateAvailability: Equatable, Sendable {
    case available
    case noSystemVPN
    case noAlternativeVPN
}

struct VPNRecoverySelectionSnapshot: Hashable, Sendable {
    let candidateServiceIDs: [String]
    let suggestedServiceID: String?
}

/// 복구 화면의 후보·초기 선택·CTA 허용 여부를 한 snapshot에서 결정한다.
struct VPNRecoverySelectionPolicy: Sendable {
    let candidates: [VPNService]
    let suggestedServiceID: String?
    let availability: VPNRecoveryCandidateAvailability

    init(context: VPNRecoveryContext) {
        let excludedServiceIDs: Set<String>
        let isRouteMismatch: Bool
        if case .routeDoesNotUseConnectedVPN(let activeServices) =
            context.diagnosis.failure {
            excludedServiceIDs = Set(activeServices.map(\.id))
            isRouteMismatch = true
        } else {
            excludedServiceIDs = []
            isRouteMismatch = false
        }

        candidates = context.services.filter {
            !excludedServiceIDs.contains($0.id)
        }
        if candidates.isEmpty {
            availability = isRouteMismatch && !context.services.isEmpty
                ? .noAlternativeVPN
                : .noSystemVPN
        } else {
            availability = .available
        }
        suggestedServiceID = Self.resolve(
            preferred: context.preferred,
            in: candidates
        ) ?? candidates.first?.id
    }

    var snapshot: VPNRecoverySelectionSnapshot {
        VPNRecoverySelectionSnapshot(
            candidateServiceIDs: candidates.map(\.id),
            suggestedServiceID: suggestedServiceID
        )
    }

    func revalidatedSelection(_ current: String?) -> String? {
        let candidateIDs = Set(candidates.map(\.id))
        if let current, candidateIDs.contains(current) {
            return current
        }
        guard let suggestedServiceID,
              candidateIDs.contains(suggestedServiceID)
        else {
            return nil
        }
        return suggestedServiceID
    }

    func permitsConnection(to serviceID: String?) -> Bool {
        guard let serviceID else {
            return false
        }
        return candidates.contains { $0.id == serviceID }
    }

    private static func resolve(
        preferred: VPNServiceReference?,
        in candidates: [VPNService]
    ) -> String? {
        guard let preferred else {
            return nil
        }
        if let serviceID = preferred.serviceID,
           candidates.contains(where: { $0.id == serviceID }) {
            return serviceID
        }
        let identifiers = [
            preferred.legacyIdentifier,
            preferred.displayName,
        ].compactMap { $0 }
        return candidates.first {
            identifiers.contains($0.id) || identifiers.contains($0.name)
        }?.id
    }
}

@MainActor
@Observable
final class VPNRecoveryActionState {
    private(set) var isInProgress = false

    @discardableResult
    func perform(
        _ operation: @escaping @MainActor () async -> Void
    ) async -> Bool {
        guard !isInProgress else {
            return false
        }
        isInProgress = true
        defer {
            isInProgress = false
        }
        await operation()
        return true
    }
}

/// 대상 연결 진단을 사용자에게 보여 줄 문구로 바꾸는 순수 프레젠테이션 계층.
///
/// 서비스 UUID는 정상 요약에 포함하지 않는다. 식별할 수 없는 터널도 임의의 VPN 이름을
/// 붙이지 않고 그대로 표시한다.
public struct VPNPresentation: Sendable {
    public let language: VPNPresentationLanguage

    public init(language: VPNPresentationLanguage = .system) {
        self.language = language
    }

    public func summary(for diagnosis: VPNConnectivityDiagnosis) -> String {
        switch diagnosis.path {
        case .direct(let interface):
            return text("path.direct", interface)
        case .vpn(let service):
            return text(
                "path.vpn",
                service.name,
                service.providerBundleID,
                service.interfaceName ?? text("value.interface_unknown")
            )
        case .unidentifiedTunnel(let interface):
            return text("path.unidentified_tunnel", interface)
        case .unavailable:
            return text("path.unavailable")
        }
    }

    public func title(for diagnosis: VPNConnectivityDiagnosis) -> String {
        text(
            diagnosis.reachable ? "title.connected" : "title.unreachable",
            diagnosis.target.displayName
        )
    }

    public func recoveryMessage(for failure: VPNConnectivityFailure) -> String {
        switch failure {
        case .dnsResolutionFailed:
            return text("failure.dns")
        case .noRoute:
            return text("failure.no_route")
        case .routeDoesNotUseConnectedVPN:
            return text("failure.route_mismatch")
        case .targetDidNotRespond(let path):
            switch path {
            case .vpn, .unidentifiedTunnel:
                return text("failure.target_vpn")
            case .direct, .unavailable:
                return text("failure.target_direct")
            }
        case .diagnosisUnavailable(let message):
            guard !message.isEmpty else {
                return text("failure.unavailable_generic")
            }
            return text("failure.unavailable", message)
        }
    }

    func serviceStatus(_ status: VPNServiceStatus) -> String {
        switch status {
        case .connected:
            return text("status.connected")
        case .disconnected:
            return text("status.disconnected")
        case .connecting:
            return text("status.connecting")
        case .disconnecting:
            return text("status.disconnecting")
        case .invalid:
            return text("status.invalid")
        }
    }

    func localized(_ key: String, _ arguments: CVarArg...) -> String {
        text(key, arguments: arguments)
    }

    func checkedAt(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func text(_ key: String, _ arguments: CVarArg...) -> String {
        text(key, arguments: arguments)
    }

    private func text(_ key: String, arguments: [CVarArg]) -> String {
        let format = localizedBundle.localizedString(
            forKey: key,
            value: key,
            table: nil
        )
        return String(format: format, locale: locale, arguments: arguments)
    }

    private var locale: Locale {
        switch language {
        case .system:
            return .current
        case .korean:
            return Locale(identifier: "ko_KR")
        case .english:
            return Locale(identifier: "en_US")
        }
    }

    private var localizedBundle: Bundle {
        let baseBundle = ResourceBundle.named(
            "swiftkit_VPNKit",
            fallback: .main
        )
        let localization: String
        switch language {
        case .system:
            return baseBundle
        case .korean:
            localization = "ko"
        case .english:
            localization = "en"
        }

        guard let path = baseBundle.path(
            forResource: localization,
            ofType: "lproj"
        ) else {
            return baseBundle
        }
        return Bundle(path: path) ?? baseBundle
    }
}
