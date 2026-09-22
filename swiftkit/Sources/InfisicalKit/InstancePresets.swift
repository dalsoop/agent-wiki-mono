import Foundation

/// Known self-hosted Infisical bases and pure URL helpers for onboarding.
///
/// Values are non-secret. Prefer the first entry when seeding an empty
/// onboarding field; the user can still type any base or pick another preset.
///
/// Default onboarding host is the InfisicalCerts recommended ranode lab DNS
/// (EndpointRouterKit bundled key `infisical`). Do not add a second preset URL.
public enum InfisicalInstancePresets: Sendable {
    public struct Preset: Sendable, Equatable, Identifiable {
        public var id: String { url }
        /// Short UI label (not localized — host identity).
        public let label: String
        public let url: String
        public init(label: String, url: String) {
            self.label = label
            self.url = url
        }
    }

    /// InfisicalCerts recommended host — same value as EndpointRouterKit `infisical` bundled default.
    public static let ranodeLab = Preset(
        label: "ranode lab",
        url: "https://infisical.local.ranode.net"
    )

    public static let all: [Preset] = [ranodeLab]

    /// Default when the onboarding field is empty.
    public static var preferred: Preset { ranodeLab }

    /// Strip trailing slashes; return empty string if only whitespace.
    public static func normalizeBase(_ raw: String) -> String {
        var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.count > 1 && base.hasSuffix("/") {
            base.removeLast()
        }
        return base
    }

    /// `https://host/login` for browser SSO. Nil if base is empty/invalid.
    public static func loginURL(instanceBase: String) -> URL? {
        let base = normalizeBase(instanceBase)
        guard !base.isEmpty else { return nil }
        // Require a scheme so openURL does not treat the string as a file path.
        let withScheme: String
        if base.lowercased().hasPrefix("http://") || base.lowercased().hasPrefix("https://") {
            withScheme = base
        } else {
            withScheme = "https://\(base)"
        }
        return URL(string: withScheme + "/login")
    }
}
