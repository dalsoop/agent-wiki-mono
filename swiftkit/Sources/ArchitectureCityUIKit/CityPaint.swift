#if os(macOS)
import AppKit
import ArchitectureCityKit

public enum CityPaint {
    public static func color(role: CityRole, usage: CityUsage, face: CityFace) -> NSColor {
        if usage == .unused {
            return NSColor(calibratedWhite: 0.38, alpha: 0.55)
        }
        let base: NSColor
        switch role {
        case .route: base = .systemBlue
        case .controller: base = .systemIndigo
        case .action, .query: base = .systemPurple
        case .service: base = .systemOrange
        case .model: base = .systemPink
        case .dto: base = .systemBrown
        case .enumeration: base = .systemCyan
        case .job: base = .systemYellow
        case .support: base = .systemGray
        case .page: base = .systemGreen
        case .component: base = .systemTeal
        case .runtime: base = .systemMint
        case .view: base = .systemGreen
        case .migration: base = .systemGray
        case .test: base = .systemYellow
        }
        let painted = role == .support && face == .frontend ? NSColor.systemMint : base
        return usage == .live ? painted : painted.withAlphaComponent(0.72)
    }
}
#endif
