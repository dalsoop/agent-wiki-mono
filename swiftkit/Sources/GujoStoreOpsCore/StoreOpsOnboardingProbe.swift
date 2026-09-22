import Foundation

/// 온보딩 단계별 라이브 판정.
public enum StoreOpsOnboardingStepStatus: String, Sendable, Codable {
    case done
    case todo
    case blocked
    case unknown
}

public struct StoreOpsOnboardingSnapshot: Sendable, Equatable {
    public var tokenSet: Bool
    public var healthOK: Bool
    public var opsAuth: String?
    public var packageCount: Int
    public var adbAvailable: Bool
    public var localReadyCount: Int
    public var serverDeviceCount: Int
    public var runnersOnline: Int
    public var lastError: String?
    /// Mac adb 사용성 진단 (unauthorized / 케이블 등).
    public var adbDiagnosis: AdbDiagnosis?
    /// service-ops fleet health ready?
    public var serviceOpsReady: Bool

    public init(
        tokenSet: Bool = false,
        healthOK: Bool = false,
        opsAuth: String? = nil,
        packageCount: Int = 0,
        adbAvailable: Bool = false,
        localReadyCount: Int = 0,
        serverDeviceCount: Int = 0,
        runnersOnline: Int = 0,
        lastError: String? = nil,
        adbDiagnosis: AdbDiagnosis? = nil,
        serviceOpsReady: Bool = false
    ) {
        self.tokenSet = tokenSet
        self.healthOK = healthOK
        self.opsAuth = opsAuth
        self.packageCount = packageCount
        self.adbAvailable = adbAvailable
        self.localReadyCount = localReadyCount
        self.serverDeviceCount = serverDeviceCount
        self.runnersOnline = runnersOnline
        self.lastError = lastError
        self.adbDiagnosis = adbDiagnosis
        self.serviceOpsReady = serviceOpsReady
    }

    public func status(for probeKey: String?) -> StoreOpsOnboardingStepStatus {
        guard let key = probeKey else { return .unknown }
        switch key {
        case "doctor":
            return doctorStatus()
        case "token":
            return tokenStatus()
        case "adb":
            return adbStatus()
        case "serverDevice":
            return serverDeviceStatus()
        case "installReady":
            return installReadyStatus()
        case "runner":
            return runnerStatus()
        case "serviceOps":
            return serviceOpsStatus()
        default:
            return .unknown
        }
    }

    private func doctorStatus() -> StoreOpsOnboardingStepStatus {
        (tokenSet && healthOK && packageCount > 0) ? .done : .todo
    }

    private func tokenStatus() -> StoreOpsOnboardingStepStatus {
        guard tokenSet else { return .todo }
        if opsAuth == "required", !tokenSet { return .blocked }
        return (tokenSet && healthOK) ? .done : .todo
    }

    private func adbStatus() -> StoreOpsOnboardingStepStatus {
        #if os(macOS)
        guard let diagnosis = adbDiagnosis else {
            return adbAvailable ? (localReadyCount > 0 ? .done : .todo) : .blocked
        }
        if diagnosis.isReady { return .done }
        switch diagnosis.kind {
        case .adbMissing, .unauthorized, .offline:
            return .blocked
        default:
            return .todo
        }
        #else
        return .unknown
        #endif
    }

    private func serverDeviceStatus() -> StoreOpsOnboardingStepStatus {
        guard tokenSet && healthOK else { return .blocked }
        return serverDeviceCount > 0 ? .done : .todo
    }

    private func installReadyStatus() -> StoreOpsOnboardingStepStatus {
        guard tokenSet && healthOK && packageCount != 0 else { return .blocked }
        guard serverDeviceCount != 0 else { return .blocked }
        #if os(macOS)
        guard localReadyCount != 0 else { return .todo } // job 은 가능, 실 install 은 adb 필요
        #endif
        return .done // 준비됨 — 설치 실행은 사람/버튼
    }

    private func runnerStatus() -> StoreOpsOnboardingStepStatus {
        guard tokenSet && healthOK else { return .blocked }
        return runnersOnline > 0 ? .done : .todo
    }

    private func serviceOpsStatus() -> StoreOpsOnboardingStepStatus {
        #if os(macOS)
        return serviceOpsReady ? .done : .todo
        #else
        return .unknown
        #endif
    }

    public var headline: String {
        var parts: [String] = []
        parts.append(tokenSet ? "token✓" : "token✗")
        parts.append(healthOK ? "health✓" : "health✗")
        parts.append("pkg \(packageCount)")
        #if os(macOS)
        if let d = adbDiagnosis {
            parts.append(d.headline)
        } else {
            parts.append(adbAvailable ? "adb✓" : "adb✗")
            parts.append("local \(localReadyCount)")
        }
        #endif
        parts.append("serverDev \(serverDeviceCount)")
        parts.append("runners \(runnersOnline)")
        return parts.joined(separator: " · ")
    }
}

public enum StoreOpsOnboardingProbe {
    /// 네트워크 + (Mac) adb 를 한 번 스캔.
    public static func snapshot(client: StoreOpsClient = OpsPreferences.makeClient()) async -> StoreOpsOnboardingSnapshot {
        OpsPreferences.loadTokenFileIfNeeded()
        let probeClient = client
        var snap = StoreOpsOnboardingSnapshot(tokenSet: OpsPreferences.bearerToken != nil)
        do {
            let h = try await probeClient.health()
            snap.healthOK = h.ok
            snap.opsAuth = h.opsAuth
            snap.runnersOnline = h.runnersOnline ?? 0
            let pkgs = try await probeClient.listPackages()
            snap.packageCount = pkgs.count
            let devs = try await probeClient.listDevices()
            snap.serverDeviceCount = devs.count
        } catch {
            snap.lastError = OpsPreferences.humanize(error)
            snap.healthOK = false
        }
        #if os(macOS)
        let adb = AdbClient()
        let diag = await adb.diagnose()
        snap.adbDiagnosis = diag
        snap.adbAvailable = diag.adbAvailable
        snap.localReadyCount = diag.readyCount
        if !diag.isReady, snap.lastError == nil {
            snap.lastError = diag.title + " — " + diag.summary
        }
        let fleet = await GujoServiceOpsFleet.snapshot()
        snap.serviceOpsReady = fleet.health == "ready"
        StateMirrorAdoption.publish(
            status: fleet.health == "ready" && snap.tokenSet ? "ok" : "degraded",
            fleet: fleet,
            tokenSet: snap.tokenSet
        )
        #endif
        return snap
    }
}
