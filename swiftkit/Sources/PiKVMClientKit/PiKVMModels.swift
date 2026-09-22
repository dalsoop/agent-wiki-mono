import Foundation

/// kvmd 가 돌려주는 실패. `{ok:false, result:{error, error_msg}}` 봉투에서 나온다.
public enum PiKVMError: Error, Sendable, Equatable {
    /// 자격증명 거절(401) 또는 `UnauthorizedError`.
    case unauthorized
    /// kvmd 가 이름 붙인 도메인 오류 — 예: `IsBusyError`, `OperationError`.
    case api(error: String, message: String?)
    /// HTTP 계층 실패(kvmd 봉투가 아닌 응답). nginx 502 처럼 **kvmd 하위 데몬이 죽은 경우**가 여기 온다.
    case http(status: Int, body: String)
    case decoding(String)
    case transport(String)
    /// 요청 자체를 만들 수 없음(잘못된 호스트 등).
    case badRequest(String)

    public var isUnauthorized: Bool { self == .unauthorized }
}

extension PiKVMError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "인증 거절 — 사용자 이름 또는 비밀번호가 맞지 않다"
        case let .api(error, message):
            return message.map { "\(error): \($0)" } ?? error
        case let .http(status, body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return "HTTP \(status)" + (trimmed.isEmpty ? "" : " — \(trimmed.prefix(200))")
        case let .decoding(detail):
            return "응답 해석 실패 — \(detail)"
        case let .transport(detail):
            return "연결 실패 — \(detail)"
        case let .badRequest(detail):
            return "요청 구성 실패 — \(detail)"
        }
    }
}

// MARK: - /api/info

public struct PiKVMSystemInfo: Sendable, Equatable, Codable {
    public var kvmdVersion: String
    public var streamerApp: String?
    public var streamerVersion: String?
    public var platform: String?
    public var kernelRelease: String?
    /// 인증이 켜져 있나(꺼져 있으면 자격증명 없이도 제어된다).
    public var authEnabled: Bool
    /// 켜져 있는 kvmd 확장 데몬 이름들 — 예: janus(WebRTC), media, webterm, ipmi.
    public var enabledExtras: [String]

    public var cpuTemperatureC: Double?
    public var cpuPercent: Double?
    public var memoryPercent: Double?
    /// 라즈베리파이 전원 부족 경고. 켜지면 캡처·USB 가 불안정해진다.
    public var undervoltageNow: Bool
    public var undervoltagePast: Bool
    public var throttledNow: Bool
    public var throttledPast: Bool

    public struct Metrics: Sendable, Equatable {
        public var cpuTemperatureC: Double?
        public var cpuPercent: Double?
        public var memoryPercent: Double?
        public var undervoltageNow: Bool
        public var undervoltagePast: Bool
        public var throttledNow: Bool
        public var throttledPast: Bool

        public init(
            cpuTemperatureC: Double? = nil,
            cpuPercent: Double? = nil,
            memoryPercent: Double? = nil,
            undervoltageNow: Bool = false,
            undervoltagePast: Bool = false,
            throttledNow: Bool = false,
            throttledPast: Bool = false
        ) {
            self.cpuTemperatureC = cpuTemperatureC
            self.cpuPercent = cpuPercent
            self.memoryPercent = memoryPercent
            self.undervoltageNow = undervoltageNow
            self.undervoltagePast = undervoltagePast
            self.throttledNow = throttledNow
            self.throttledPast = throttledPast
        }
    }

    public init(
        kvmdVersion: String,
        streamerApp: String? = nil,
        streamerVersion: String? = nil,
        platform: String? = nil,
        kernelRelease: String? = nil,
        authEnabled: Bool = true,
        enabledExtras: [String] = [],
        metrics: Metrics = Metrics()
    ) {
        self.kvmdVersion = kvmdVersion
        self.streamerApp = streamerApp
        self.streamerVersion = streamerVersion
        self.platform = platform
        self.kernelRelease = kernelRelease
        self.authEnabled = authEnabled
        self.enabledExtras = enabledExtras
        self.cpuTemperatureC = metrics.cpuTemperatureC
        self.cpuPercent = metrics.cpuPercent
        self.memoryPercent = metrics.memoryPercent
        self.undervoltageNow = metrics.undervoltageNow
        self.undervoltagePast = metrics.undervoltagePast
        self.throttledNow = metrics.throttledNow
        self.throttledPast = metrics.throttledPast
    }

    /// 사람이 읽을 건강 경고 — 없으면 빈 배열.
    public var healthWarnings: [String] {
        var out: [String] = []
        if undervoltageNow { out.append("전원 부족(현재)") }
        else if undervoltagePast { out.append("전원 부족(과거 기록)") }
        if throttledNow { out.append("주파수 제한(현재)") }
        else if throttledPast { out.append("주파수 제한(과거 기록)") }
        if let t = cpuTemperatureC, t >= 75 { out.append(String(format: "CPU 온도 %.0f°C", t)) }
        return out
    }
}

// MARK: - /api/atx

/// 대상 PC 의 전원 배선(ATX 헤더) 상태.
public struct PiKVMPowerState: Sendable, Equatable, Codable {
    public var enabled: Bool
    /// 직전 동작이 아직 진행 중(버튼 누름 유지 시간).
    public var busy: Bool
    /// 전원 LED — 대상 PC 가 켜져 있나.
    public var powerLED: Bool
    /// 디스크 활동 LED.
    public var hddLED: Bool

    public init(enabled: Bool, busy: Bool, powerLED: Bool, hddLED: Bool) {
        self.enabled = enabled
        self.busy = busy
        self.powerLED = powerLED
        self.hddLED = hddLED
    }

    public var isOn: Bool { powerLED }
}

/// ATX 버튼 동작. kvmd `/api/atx/click?button=` 의 값과 1:1.
public enum PiKVMPowerAction: String, Sendable, CaseIterable, Codable {
    /// 전원 버튼 짧게 — 켜기 / OS 에 정상 종료 요청.
    case power
    /// 전원 버튼 길게(5초) — 강제 차단. OS 를 거치지 않으므로 데이터 손실 위험.
    case powerLong = "power_long"
    /// 리셋 버튼.
    case reset

    /// 되돌릴 수 없거나 데이터 손실 위험이 있어 확인을 받아야 하는 동작.
    public var isDestructive: Bool {
        switch self {
        case .power: return false
        case .powerLong, .reset: return true
        }
    }

    public var koreanLabel: String {
        switch self {
        case .power: return "전원 버튼 (짧게)"
        case .powerLong: return "강제 전원 차단 (길게)"
        case .reset: return "리셋"
        }
    }
}

// MARK: - /api/gpio (KVM 스위치)

/// KVM 스위치의 포트 하나. kvmd GPIO 의 `view` 표(사람이 붙인 이름)와 `state`(실시간)를 합친 것.
public struct PiKVMPort: Sendable, Equatable, Identifiable, Codable {
    /// 누르기용 출력 채널 — 예: `ch1_button`.
    public var buttonChannel: String
    /// 활성 표시용 입력 채널 — 예: `ch1_led`. 없는 스위치도 있다.
    public var ledChannel: String?
    /// 사람이 붙인 이름 — 예: "60 서버". kvmd 설정에서 온다.
    public var label: String
    /// 지금 이 포트가 선택돼 있나(LED 입력 기준).
    public var isActive: Bool
    /// 하드웨어가 응답 중인가.
    public var isOnline: Bool
    public var isBusy: Bool
    /// kvmd 설정이 확인 창을 요구하는 포트.
    public var requiresConfirm: Bool

    public var id: String { buttonChannel }

    public init(
        buttonChannel: String,
        ledChannel: String? = nil,
        label: String,
        isActive: Bool = false,
        isOnline: Bool = true,
        isBusy: Bool = false,
        requiresConfirm: Bool = false
    ) {
        self.buttonChannel = buttonChannel
        self.ledChannel = ledChannel
        self.label = label
        self.isActive = isActive
        self.isOnline = isOnline
        self.isBusy = isBusy
        self.requiresConfirm = requiresConfirm
    }
}

/// GPIO 로 노출된 KVM 스위치 전체.
public struct PiKVMSwitchState: Sendable, Equatable, Codable {
    /// 스위치 이름 — 예: "BliSwitch v1". 표시용 헤더에서 온다.
    public var title: String?
    public var ports: [PiKVMPort]
    /// 포트가 아닌 나머지 GPIO 출력(예: `__v3_usb_breaker__`) 이름들.
    public var otherOutputs: [String]

    public init(title: String? = nil, ports: [PiKVMPort] = [], otherOutputs: [String] = []) {
        self.title = title
        self.ports = ports
        self.otherOutputs = otherOutputs
    }

    public var activePort: PiKVMPort? { ports.first(where: \.isActive) }
    /// 스위치가 물려 있나 — 포트가 하나도 없으면 단일 대상 PiKVM 이다.
    public var hasSwitch: Bool { !ports.isEmpty }
}

// MARK: - /api/msd (가상 미디어)

public struct PiKVMImage: Sendable, Equatable, Identifiable, Codable {
    public var name: String
    public var sizeBytes: Int64
    /// 업로드가 끝나 사용 가능한가. 중단된 업로드는 false.
    public var complete: Bool

    public var id: String { name }

    public init(name: String, sizeBytes: Int64, complete: Bool = true) {
        self.name = name
        self.sizeBytes = sizeBytes
        self.complete = complete
    }
}

/// 가상 대용량 저장장치 — 대상 PC 에 USB 드라이브/CD 로 붙는다.
public struct PiKVMMassStorageState: Sendable, Equatable, Codable {
    public var enabled: Bool
    public var online: Bool
    public var busy: Bool
    /// 대상 PC 에 지금 연결돼 있나.
    public var connected: Bool
    /// 연결된(또는 선택된) 이미지 이름.
    public var image: String?
    /// CD-ROM 으로 붙이나(false 면 쓰기 가능 플래시).
    public var isCDROM: Bool
    public var isWritable: Bool
    public var images: [PiKVMImage]
    public var freeBytes: Int64
    public var totalBytes: Int64
    /// 업로드 진행 중인 이미지 이름.
    public var uploading: String?

    public struct Volume: Sendable, Equatable {
        public var images: [PiKVMImage]
        public var freeBytes: Int64
        public var totalBytes: Int64
        public var uploading: String?

        public init(
            images: [PiKVMImage] = [],
            freeBytes: Int64 = 0,
            totalBytes: Int64 = 0,
            uploading: String? = nil
        ) {
            self.images = images
            self.freeBytes = freeBytes
            self.totalBytes = totalBytes
            self.uploading = uploading
        }
    }

    public init(
        enabled: Bool,
        online: Bool,
        busy: Bool,
        connected: Bool,
        image: String? = nil,
        isCDROM: Bool = true,
        isWritable: Bool = false,
        volume: Volume = Volume()
    ) {
        self.enabled = enabled
        self.online = online
        self.busy = busy
        self.connected = connected
        self.image = image
        self.isCDROM = isCDROM
        self.isWritable = isWritable
        self.images = volume.images
        self.freeBytes = volume.freeBytes
        self.totalBytes = volume.totalBytes
        self.uploading = volume.uploading
    }
}

// MARK: - /api/hid (키보드·마우스)

public struct PiKVMHIDState: Sendable, Equatable, Codable {
    public var enabled: Bool
    public var busy: Bool
    /// 대상 PC 가 USB 를 인식했나. 파이 하드웨어에 따라 알 수 없음(nil)일 수 있다.
    public var connected: Bool?
    public var keyboardOnline: Bool
    public var mouseOnline: Bool
    /// 절대좌표 마우스(모드 전환이 필요 없다). false 면 상대좌표.
    public var mouseAbsolute: Bool
    public var capsLock: Bool
    public var numLock: Bool
    public var scrollLock: Bool
    /// 마우스 지글러 — 대상 PC 화면보호기를 막는다.
    public var jigglerEnabled: Bool
    public var jigglerActive: Bool
    public var jigglerIntervalSeconds: Int

    public struct Indicators: Sendable, Equatable {
        public var capsLock: Bool
        public var numLock: Bool
        public var scrollLock: Bool
        public var jigglerEnabled: Bool
        public var jigglerActive: Bool
        public var jigglerIntervalSeconds: Int

        public init(
            capsLock: Bool = false,
            numLock: Bool = false,
            scrollLock: Bool = false,
            jigglerEnabled: Bool = false,
            jigglerActive: Bool = false,
            jigglerIntervalSeconds: Int = 0
        ) {
            self.capsLock = capsLock
            self.numLock = numLock
            self.scrollLock = scrollLock
            self.jigglerEnabled = jigglerEnabled
            self.jigglerActive = jigglerActive
            self.jigglerIntervalSeconds = jigglerIntervalSeconds
        }
    }

    public init(
        enabled: Bool,
        busy: Bool,
        connected: Bool? = nil,
        keyboardOnline: Bool = false,
        mouseOnline: Bool = false,
        mouseAbsolute: Bool = true,
        indicators: Indicators = Indicators()
    ) {
        self.enabled = enabled
        self.busy = busy
        self.connected = connected
        self.keyboardOnline = keyboardOnline
        self.mouseOnline = mouseOnline
        self.mouseAbsolute = mouseAbsolute
        self.capsLock = indicators.capsLock
        self.numLock = indicators.numLock
        self.scrollLock = indicators.scrollLock
        self.jigglerEnabled = indicators.jigglerEnabled
        self.jigglerActive = indicators.jigglerActive
        self.jigglerIntervalSeconds = indicators.jigglerIntervalSeconds
    }

    /// 지금 보낸 키가 대상 PC 에 실제로 닿나.
    ///
    /// PiKVM 은 **닿지 않아도 요청을 성공으로 받는다** — USB 가젯이 열거되지 않았으면
    /// kvmd 가 이벤트를 버리고 `200 {ok:true}` 를 돌려준다. 그래서 "보냈다" 는 응답만 믿으면
    /// 허공에 친 것을 성공으로 오해한다. 보내기 전에 이걸 본다.
    public var canType: Bool { enabled && keyboardOnline }

    /// 왜 키가 안 닿는지. 닿는 상태면 nil.
    public var typingBlockedReason: String? {
        if !enabled { return "이 PiKVM 은 HID(키보드·마우스)가 꺼져 있다" }
        if !keyboardOnline {
            return "대상 PC 가 USB 키보드를 아직 인식하지 않았다(PC 가 꺼졌거나, 부팅 전이거나, 케이블이 빠졌다)"
        }
        return nil
    }

    /// 마우스도 같은 이유로 안 닿을 수 있다(키보드만 살아 있는 경우가 있다).
    public var pointingBlockedReason: String? {
        if !enabled { return "이 PiKVM 은 HID(키보드·마우스)가 꺼져 있다" }
        if !mouseOnline { return "대상 PC 가 USB 마우스를 아직 인식하지 않았다" }
        return nil
    }
}

// MARK: - /api/streamer (영상)

public struct PiKVMStreamerState: Sendable, Equatable, Codable {
    /// ustreamer 프로세스가 지금 돌고 있나.
    ///
    /// **false 는 고장이 아니다.** kvmd 는 스트리머를 상주시키지 않는다(`streamer.forever: false`) —
    /// 보는 세션이 생기면 켜고, 마지막 세션이 떠나면 `shutdown_delay`(기본 10초) 뒤 끈다.
    /// 아무도 안 볼 때 `streamer: null` 인 것이 정상이다. 켜려면 `PiKVMStreamSession` 으로
    /// kvmd 세션을 열면 된다 — MJPEG 주소만 때려서는 안 켜지고 nginx 502 만 돌아온다
    /// (2026-08-10 실측: ws 를 열자 4초 안에 기동).
    public var running: Bool
    public var desiredFPS: Int
    public var quality: Int?
    public var h264Bitrate: Int?
    public var supportsH264: Bool
    /// 실제 캡처 중인 해상도 — 스트리머가 돌 때만.
    public var capturedResolution: String?
    /// 실제 나오는 프레임률.
    public var capturedFPS: Int?
    /// 캡처 입력에 신호가 있나(케이블·대상 PC 전원).
    public var hasSignal: Bool?
    /// 장비가 허용하는 값 범위. UI 슬라이더를 여기에 맞춘다 — 하드코딩하면 설치본마다 어긋난다.
    public var fpsRange: ClosedRange<Int>
    public var qualityRange: ClosedRange<Int>

    public struct Capture: Sendable, Equatable {
        public var capturedResolution: String?
        public var capturedFPS: Int?
        public var hasSignal: Bool?

        public init(
            capturedResolution: String? = nil,
            capturedFPS: Int? = nil,
            hasSignal: Bool? = nil
        ) {
            self.capturedResolution = capturedResolution
            self.capturedFPS = capturedFPS
            self.hasSignal = hasSignal
        }
    }

    public init(
        running: Bool,
        desiredFPS: Int = 0,
        quality: Int? = nil,
        h264Bitrate: Int? = nil,
        supportsH264: Bool = false,
        capture: Capture = Capture(),
        fpsRange: ClosedRange<Int> = 0...70,
        qualityRange: ClosedRange<Int> = 1...100
    ) {
        self.running = running
        self.desiredFPS = desiredFPS
        self.quality = quality
        self.h264Bitrate = h264Bitrate
        self.supportsH264 = supportsH264
        self.capturedResolution = capture.capturedResolution
        self.capturedFPS = capture.capturedFPS
        self.hasSignal = capture.hasSignal
        self.fpsRange = fpsRange
        self.qualityRange = qualityRange
    }

    /// 지금 화면을 볼 수 없는 이유 — 볼 수 있으면 nil.
    ///
    /// "대기 중"과 "신호 없음"을 구분한다. 둘을 뭉개면 사용자가 정상 대기 상태를 고장으로 읽고
    /// 엉뚱한 데를 뒤진다(초기 구현이 그랬다).
    public var offlineReason: String? {
        if !running { return "보는 사람이 없어 꺼져 있다 — 화면을 켜면 PiKVM 이 스트리머를 시작한다" }
        if hasSignal == false { return "캡처 입력에 신호가 없다 — 대상 PC 가 꺼졌거나 HDMI 가 빠졌다" }
        return nil
    }

    /// 사람이 손댈 것이 있는 상태인가. 대기 중은 아무 문제가 아니다.
    public var needsAttention: Bool { running && hasSignal == false }
}
