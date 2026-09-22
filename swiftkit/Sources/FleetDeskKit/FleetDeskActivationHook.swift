#if canImport(AppKit)
import AppKit

@_silgen_name("FleetDeskActivationHookForceLink")
func FleetDeskActivationHookForceLink()

/// C `hook.m` 이 `setActivationPolicy:` IMP 를 바꾼다. 여기선 링크만 강제하고
/// 숨김 여부를 알려 준다.
enum FleetDeskActivationHook {
    static func install() {
        FleetDeskActivationHookForceLink()
    }
}

@_silgen_name("FleetDeskShouldForceAccessory")
func FleetDeskShouldForceAccessoryC() -> Bool

@_cdecl("FleetDeskInstallActivationHook")
public func FleetDeskInstallActivationHook() {
    FleetDeskApply.installHook()
}
#endif
