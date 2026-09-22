import Foundation
import CryptoKit

// MARK: - Host Thermal Observation
/// 이 맥이 지금 내놓는 열 관측. 정상 체온 상수가 아니다.
public enum CognitiveHostThermalObservation {
    public static func currentLevel() -> Double {
        Double(ProcessInfo.processInfo.thermalState.rawValue)
    }
}

// MARK: - Host Hardware Telemetry (Layer 1)
/// 호스트 하드웨어의 SHA256 해시 연산 지연시간 실측 엔진 (Layer 1 미세 물리 텔레메트리)
public enum HostHardwareTelemetry {
    /// 이 호스트에서 SHA256 해시를 지정 라운드만큼 실행한 시간(ms) 실측.
    public static func measureLatency(hashRounds: Int) -> Double {
        var buffer = Data(count: 2048)
        var i = 0
        while i < buffer.count {
            buffer[i] = UInt8(i % 256)
            i += 1
        }
        let start = DispatchTime.now().uptimeNanoseconds
        var remaining = hashRounds
        while remaining > 0 {
            _ = SHA256.hash(data: buffer)
            remaining -= 1
        }
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
    }

    /// 지정된 라운드 수의 SHA256 해시 지연시간을 count회 반복 실측하여 표본 배열을 반환.
    public static func measureLatencies(hashRounds: Int, count: Int) -> [Double] {
        var samples: [Double] = []
        var i = 0
        while i < count {
            samples.append(measureLatency(hashRounds: hashRounds))
            i += 1
        }
        return samples
    }
}
