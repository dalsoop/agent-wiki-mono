import CoreLocation
import Foundation

/// 위치 TCC 정본. 앱이 `CLLocationManager` 를 직접 두지 않게 여기만 산다.
///
/// macOS 는 Wi-Fi SSID 를 위치 정보로 취급한다. 프롬프트는 Always 가 안정적이다 —
/// WhenInUse 만 부르면 조용히 무시되는 실측이 있다(2026-08-15 VPN WireGuard).
enum LocationAuthorization {
    static var status: CLAuthorizationStatus {
        CLLocationManager().authorizationStatus
    }

    static var isGranted: Bool {
        switch status {
        case .authorized, .authorizedAlways, .authorizedWhenInUse: true
        default: false
        }
    }

    static var isNotDetermined: Bool { status == .notDetermined }

    static func request() {
        Holder.shared.request()
    }

    final class Holder: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
        static let shared = Holder()
        private let manager = CLLocationManager()

        override init() {
            super.init()
            manager.delegate = self
        }

        func request() {
            manager.requestAlwaysAuthorization()
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            NotificationCenter.default.post(
                name: .permissionAuthorizationDidChange, object: nil)
        }
    }
}

public extension Notification.Name {
    static let permissionAuthorizationDidChange = Notification.Name(
        "PermissionKit.authorizationDidChange")
}
