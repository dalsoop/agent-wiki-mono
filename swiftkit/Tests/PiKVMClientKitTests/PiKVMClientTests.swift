import Foundation
import HTTPClientKit
import Testing

@testable import PiKVMClientKit

/// 요청을 기록하고 미리 정한 응답을 돌려주는 목 전송.
/// 실제 장비(192.168.2.16, PiKVM 4.121 + BliSwitch v1)에서 받아 온 응답을 그대로 쓴다.
private final class MockHTTP: HTTPClient, @unchecked Sendable {
    struct Call: Sendable {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data?
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private let responder: @Sendable (URL) -> (Int, Data)

    var calls: [Call] { lock.withLock { _calls } }

    init(status: Int = 200, json: String) {
        let data = Data(json.utf8)
        responder = { _ in (status, data) }
    }

    init(responder: @escaping @Sendable (URL) -> (Int, Data)) {
        self.responder = responder
    }

    func send(
        method: String, url: URL, headers: [String: String], body: Data?
    ) async throws -> (status: Int, data: Data) {
        lock.withLock { _calls.append(Call(method: method, url: url, headers: headers, body: body)) }
        return responder(url)
    }
}

private func makeClient(_ http: HTTPClient) -> PiKVMClient {
    PiKVMClient(
        endpoint: PiKVMEndpoint(host: "192.168.2.16"),
        credentials: PiKVMCredentials(user: "admin", passwd: "secret"),
        http: http
    )
}

@Suite("PiKVM kvmd 계약")
struct PiKVMClientTests {

    // MARK: - 봉투·인증

    @Test("자격증명은 X-KVMD 헤더로 실린다")
    func sendsKVMDAuthHeaders() async throws {
        let http = MockHTTP(json: #"{"ok":true,"result":{"system":{"kvmd":{"version":"4.121"}}}}"#)
        _ = try await makeClient(http).systemInfo()

        let call = try #require(http.calls.first)
        #expect(call.headers["X-KVMD-User"] == "admin")
        #expect(call.headers["X-KVMD-Passwd"] == "secret")
        #expect(call.url.absoluteString == "https://192.168.2.16/api/info")
    }

    @Test("UnauthorizedError 봉투는 unauthorized 로 올라온다")
    func unauthorizedEnvelope() async throws {
        // 실제 장비가 자격증명 없이 주는 응답(HTTP 401 + 봉투).
        let http = MockHTTP(
            status: 401,
            json: #"{"ok":false,"result":{"error":"UnauthorizedError","error_msg":"Unauthorized"}}"#
        )
        await #expect(throws: PiKVMError.unauthorized) {
            _ = try await makeClient(http).systemInfo()
        }
    }

    @Test("kvmd 도메인 오류는 이름과 함께 올라온다")
    func apiErrorEnvelope() async throws {
        let http = MockHTTP(
            json: #"{"ok":false,"result":{"error":"IsBusyError","error_msg":"Performing another operation"}}"#
        )
        await #expect(throws: PiKVMError.api(error: "IsBusyError", message: "Performing another operation")) {
            _ = try await makeClient(http).powerState()
        }
    }

    @Test("봉투가 아닌 nginx 502 는 HTTP 오류로 구분된다")
    func nonEnvelopeGatewayError() async throws {
        // 하위 데몬(ustreamer)이 죽으면 nginx 가 HTML 502 를 준다 — 해석 실패가 아니라 HTTP 오류다.
        let http = MockHTTP(status: 502, json: "<html><body>502 Bad Gateway</body></html>")
        do {
            _ = try await makeClient(http).powerState()
            Issue.record("throw 했어야 한다")
        } catch let error as PiKVMError {
            guard case let .http(status, body) = error else {
                Issue.record("http 오류를 기대했다: \(error)")
                return
            }
            #expect(status == 502)
            #expect(body.contains("502"))
        }
    }

    // MARK: - /api/info

    @Test("info 는 버전·건강·활성 확장을 뽑는다")
    func decodesSystemInfo() async throws {
        let http = MockHTTP(json: """
        {"ok":true,"result":{
          "auth":{"enabled":true},
          "extras":{"janus":{"enabled":true},"ipmi":{"enabled":false},"webterm":{"enabled":true}},
          "hw":{"health":{"cpu":{"percent":6},"mem":{"percent":24.6},"temp":{"cpu":52.095},
                "throttling":{"parsed_flags":{"undervoltage":{"now":false,"past":true},
                                              "throttled":{"now":false,"past":false}}}},
                "platform":{"base":"Raspberry Pi 4 Model B Rev 1.1"}},
          "system":{"kernel":{"release":"6.12.56-1-rpi"},
                    "kvmd":{"version":"4.121"},
                    "streamer":{"app":"ustreamer","version":"6.41"}}}}
        """)
        let info = try await makeClient(http).systemInfo()

        #expect(info.kvmdVersion == "4.121")
        #expect(info.streamerApp == "ustreamer")
        #expect(info.platform == "Raspberry Pi 4 Model B Rev 1.1")
        #expect(info.enabledExtras == ["janus", "webterm"])
        #expect(info.cpuTemperatureC == 52.095)
        #expect(info.undervoltagePast)
        #expect(!info.undervoltageNow)
        // 과거 기록만 있으면 '과거' 로 구분해 경고한다 — 지금 문제로 오인하면 헛수리를 부른다.
        #expect(info.healthWarnings == ["전원 부족(과거 기록)"])
    }

    // MARK: - /api/atx

    @Test("전원 LED 로 대상 PC 상태를 읽는다")
    func decodesPowerState() async throws {
        let http = MockHTTP(json: """
        {"ok":true,"result":{"enabled":true,"busy":false,
         "leds":{"power":true,"hdd":false},"acts":{"power":false,"reset":false}}}
        """)
        let state = try await makeClient(http).powerState()
        #expect(state.isOn)
        #expect(state.enabled)
        #expect(!state.busy)
    }

    @Test("전원 동작은 kvmd 버튼 이름으로 나간다")
    func powerActionUsesKVMDButtonNames() async throws {
        let http = MockHTTP(json: #"{"ok":true,"result":{}}"#)
        let client = makeClient(http)
        try await client.pressPower(.powerLong)

        let call = try #require(http.calls.first)
        #expect(call.method == "POST")
        #expect(call.url.absoluteString == "https://192.168.2.16/api/atx/click?button=power_long")
    }

    @Test("길게 누르기·리셋만 확인이 필요한 동작으로 분류된다")
    func destructiveActionsAreFlagged() {
        #expect(!PiKVMPowerAction.power.isDestructive)
        #expect(PiKVMPowerAction.powerLong.isDestructive)
        #expect(PiKVMPowerAction.reset.isDestructive)
    }

    // MARK: - /api/gpio (KVM 스위치)

    /// 실제 BliSwitch v1 응답(포트 이름은 사용자가 kvmd 설정에 넣은 값).
    private static let bliSwitchGPIO = """
    {"ok":true,"result":{
      "model":{
        "scheme":{
          "inputs":{"ch0_led":{},"ch1_led":{},"ch2_led":{},"ch3_led":{}},
          "outputs":{"__v3_usb_breaker__":{},"ch0_button":{},"ch1_button":{},
                     "ch2_button":{},"ch3_button":{}}},
        "view":{
          "header":{"title":[{"text":"BliSwitch v1","type":"label"}]},
          "table":[
            [{"text":"PC 1","type":"label"},{"channel":"ch0_led","type":"input"},
             {"channel":"ch0_button","confirm":false,"text":"Click","type":"output"}],
            [{"text":"60 서버","type":"label"},{"channel":"ch1_led","type":"input"},
             {"channel":"ch1_button","confirm":false,"text":"Click","type":"output"}],
            [{"text":"50 서버","type":"label"},{"channel":"ch2_led","type":"input"},
             {"channel":"ch2_button","confirm":true,"text":"Click","type":"output"}],
            [{"text":"PC 4","type":"label"},{"channel":"ch3_led","type":"input"},
             {"channel":"ch3_button","confirm":false,"text":"Click","type":"output"}]]}},
      "state":{
        "inputs":{"ch0_led":{"online":true,"state":false},"ch1_led":{"online":true,"state":true},
                  "ch2_led":{"online":true,"state":false},"ch3_led":{"online":true,"state":false}},
        "outputs":{"__v3_usb_breaker__":{"busy":false,"online":true,"state":true},
                   "ch0_button":{"busy":false,"online":true,"state":false},
                   "ch1_button":{"busy":false,"online":true,"state":true},
                   "ch2_button":{"busy":false,"online":true,"state":false},
                   "ch3_button":{"busy":true,"online":true,"state":false}}}}}
    """

    @Test("포트 이름은 채널 ID 가 아니라 사람이 붙인 라벨을 쓴다")
    func decodesSwitchPortsWithHumanLabels() async throws {
        let http = MockHTTP(json: Self.bliSwitchGPIO)
        let sw = try await makeClient(http).switchState()

        #expect(sw.title == "BliSwitch v1")
        #expect(sw.hasSwitch)
        #expect(sw.ports.map(\.label) == ["PC 1", "60 서버", "50 서버", "PC 4"])
        #expect(sw.ports.map(\.buttonChannel) == ["ch0_button", "ch1_button", "ch2_button", "ch3_button"])
        // LED 입력이 활성 포트를 정한다 — 출력 state 가 아니다.
        #expect(sw.activePort?.label == "60 서버")
        #expect(sw.ports[2].requiresConfirm)
        #expect(sw.ports[3].isBusy)
        // USB 차단기는 포트가 아니므로 포트 목록에 섞이면 안 된다.
        #expect(sw.otherOutputs == ["__v3_usb_breaker__"])
    }

    @Test("포트 전환은 해당 버튼 채널 pulse 로 나간다")
    func selectPortPulsesButtonChannel() async throws {
        let http = MockHTTP(responder: { url in
            if url.path == "/api/gpio" { return (200, Data(Self.bliSwitchGPIO.utf8)) }
            return (200, Data(#"{"ok":true,"result":{}}"#.utf8))
        })
        let client = makeClient(http)
        let sw = try await client.switchState()
        try await client.selectPort(try #require(sw.ports.first { $0.label == "50 서버" }))

        let last = try #require(http.calls.last)
        #expect(last.method == "POST")
        #expect(last.url.absoluteString == "https://192.168.2.16/api/gpio/pulse?channel=ch2_button")
    }

    @Test("view 가 없는 설치본은 채널 이름으로 폴백한다")
    func switchWithoutViewFallsBack() {
        // 스위치가 안 물린 단일 대상 PiKVM 은 view.table 자체가 없다.
        let gpio: [String: Any] = [
            "model": ["scheme": ["inputs": [:], "outputs": [:]]],
            "state": ["inputs": [:], "outputs": [:]],
        ]
        let sw = PiKVMClient.parseSwitch(gpio: gpio)
        #expect(!sw.hasSwitch)
        #expect(sw.activePort == nil)
    }

    // MARK: - /api/msd

    @Test("가상 미디어 상태와 용량을 뽑는다")
    func decodesMassStorage() async throws {
        let http = MockHTTP(json: """
        {"ok":true,"result":{"busy":false,"enabled":true,"online":true,
          "drive":{"cdrom":true,"connected":false,"image":"ubuntu.iso","rw":false},
          "storage":{"downloading":null,"uploading":null,
            "images":{"ubuntu.iso":{"size":4700000000,"complete":true},
                      "half.iso":{"size":10,"complete":false}},
            "parts":{"":{"free":24344633344,"size":24363532288,"writable":true}}}}}
        """)
        let msd = try await makeClient(http).massStorageState()

        #expect(msd.enabled)
        #expect(!msd.connected)
        #expect(msd.image == "ubuntu.iso")
        #expect(msd.isCDROM)
        #expect(msd.images.map(\.name) == ["half.iso", "ubuntu.iso"])
        #expect(msd.images.first(where: { $0.name == "half.iso" })?.complete == false)
        #expect(msd.freeBytes == 24_344_633_344)
        #expect(msd.totalBytes == 24_363_532_288)
    }

    // MARK: - /api/hid

    @Test("타이핑은 본문으로 보내고 키 이름은 질의로 보낸다")
    func typingAndKeys() async throws {
        let http = MockHTTP(json: #"{"ok":true,"result":{}}"#)
        let client = makeClient(http)
        try await client.typeText("hello")
        try await client.sendKey("Enter")

        #expect(http.calls[0].url.path == "/api/hid/print")
        #expect(http.calls[0].body == Data("hello".utf8))
        #expect(http.calls[0].headers["Content-Type"] == "text/plain")
        #expect(http.calls[1].url.absoluteString == "https://192.168.2.16/api/hid/events/send_key?key=Enter")
    }

    @Test("키보드·마우스 온라인 여부를 구분해 읽는다")
    func decodesHIDState() async throws {
        let http = MockHTTP(json: """
        {"ok":true,"result":{"busy":false,"connected":null,"enabled":true,
          "jiggler":{"active":false,"enabled":true,"interval":60},
          "keyboard":{"leds":{"caps":true,"num":false,"scroll":false},"online":false},
          "mouse":{"absolute":true,"online":true}}}
        """)
        let hid = try await makeClient(http).hidState()
        #expect(hid.enabled)
        #expect(hid.connected == nil)  // 파이가 알 수 없음 — false 로 뭉개면 안 된다
        #expect(!hid.keyboardOnline)
        #expect(hid.mouseOnline)
        #expect(hid.capsLock)
        #expect(hid.jigglerIntervalSeconds == 60)
    }

    // MARK: - /api/streamer

    @Test("streamer:null 은 고장이 아니라 '대기 중' 이다")
    func streamerNullMeansNotRunning() async throws {
        // 실제 192.168.2.16 의 현재 상태 — ustreamer 가 안 돌아 /streamer/stream 이 502 다.
        let http = MockHTTP(json: """
        {"ok":true,"result":{"features":{"h264":true,"quality":true},
          "params":{"desired_fps":40,"h264_bitrate":5000,"quality":80},
          "snapshot":{"saved":null},"streamer":null}}
        """)
        let state = try await makeClient(http).streamerState()
        #expect(!state.running)
        #expect(state.desiredFPS == 40)
        #expect(state.quality == 80)
        #expect(state.supportsH264)
        // 대기(정상)와 고장을 구분한다. 뭉개면 사용자가 멀쩡한 장비를 뜯는다.
        #expect(state.offlineReason?.contains("보는 사람이 없어") == true)
        #expect(!state.needsAttention)
    }

    @Test("스트리머가 돌면 해상도·실측 fps 를 읽고 신호 없음을 구분한다")
    func streamerRunningWithoutSignal() async throws {
        let http = MockHTTP(json: """
        {"ok":true,"result":{"features":{"h264":false},"params":{"desired_fps":30,"quality":80},
          "streamer":{"source":{"online":false,"captured_fps":0,
                                "resolution":{"width":1920,"height":1080}}}}}
        """)
        let state = try await makeClient(http).streamerState()
        #expect(state.running)
        #expect(state.capturedResolution == "1920×1080")
        #expect(state.hasSignal == false)
        #expect(state.offlineReason?.contains("신호가 없다") == true)
        // 돌고 있는데 신호가 없는 것은 사람이 볼 일이다(케이블·대상 PC 전원).
        #expect(state.needsAttention)
    }

    @Test("스냅샷 503 은 바이너리가 아니라 kvmd 오류로 올라온다")
    func snapshotFailureSurfacesAPIError() async throws {
        let http = MockHTTP(
            status: 503,
            json: #"{"ok":false,"result":{"error":"StreamerTemporarilyOfflineError","error_msg":"offline"}}"#
        )
        await #expect(throws: PiKVMError.api(error: "StreamerTemporarilyOfflineError", message: "offline")) {
            _ = try await makeClient(http).snapshotJPEG()
        }
    }

    // MARK: - 주소 구성

    @Test("스트림·websocket 주소는 스킴을 맞춰 만든다")
    func derivedURLs() {
        let tls = PiKVMClient(
            endpoint: PiKVMEndpoint(host: "192.168.2.16"),
            credentials: PiKVMCredentials(user: "a", passwd: "b"),
            http: MockHTTP(json: "{}")
        )
        #expect(tls.streamURL?.absoluteString == "https://192.168.2.16/streamer/stream")
        #expect(tls.websocketURL?.absoluteString == "wss://192.168.2.16/api/ws?stream=0")
        // 회귀: 영상용 세션은 반드시 stream=1 이다. 0 으로 열면 세션은 붙지만 kvmd 가
        // 스트리머를 안 켜서 화면이 영원히 안 나온다(2026-08-10 실측으로 밟았다).
        #expect(tls.websocketURL(wantsVideo: true)?.absoluteString
            == "wss://192.168.2.16/api/ws?stream=1")

        let plain = PiKVMClient(
            endpoint: PiKVMEndpoint(host: "kvm.lan", port: 8080, useTLS: false),
            credentials: PiKVMCredentials(user: "a", passwd: "b"),
            http: MockHTTP(json: "{}")
        )
        #expect(plain.streamURL?.absoluteString == "http://kvm.lan:8080/streamer/stream")
        #expect(plain.websocketURL?.absoluteString == "ws://kvm.lan:8080/api/ws?stream=0")
    }

    // MARK: - HID 도달성

    @Test("키보드가 온라인일 때만 키가 닿는다고 본다")
    func typingReachabilityFollowsKeyboardOnline() {
        let live = PiKVMHIDState(enabled: true, busy: false, keyboardOnline: true, mouseOnline: true)
        #expect(live.canType)
        #expect(live.typingBlockedReason == nil)
        #expect(live.pointingBlockedReason == nil)
    }

    @Test("대상 PC 가 USB 를 안 잡았으면 이유를 말하고 막는다")
    func offlineKeyboardIsBlockedWithReason() {
        // 2026-08-11 실측 상태 그대로: HID 는 켜져 있는데 대상 PC 가 꺼져 있어
        // keyboard.online·mouse.online 이 false 였고, 그런데도 kvmd 는 입력을 200 으로 받았다.
        let offline = PiKVMHIDState(
            enabled: true, busy: false, keyboardOnline: false, mouseOnline: false)
        #expect(!offline.canType)
        let reason = offline.typingBlockedReason
        #expect(reason != nil)
        // 무엇을 해야 하는지가 문구에 있어야 한다 — "오프라인" 만으로는 사람이 못 움직인다.
        #expect(reason?.contains("USB") == true)
        #expect(offline.pointingBlockedReason != nil)
    }

    @Test("HID 자체가 꺼진 장비는 키보드 온라인과 다른 이유를 준다")
    func hidDisabledHasItsOwnReason() {
        let disabled = PiKVMHIDState(enabled: false, busy: false, keyboardOnline: true)
        #expect(!disabled.canType)
        #expect(disabled.typingBlockedReason?.contains("HID") == true)
        // 키보드는 온라인이라고 보고돼도 HID 가 꺼져 있으면 못 보낸다 —
        // 두 이유가 같은 문구로 뭉개지면 사람이 엉뚱한 조치를 한다.
        #expect(disabled.typingBlockedReason != PiKVMHIDState(
            enabled: true, busy: false, keyboardOnline: false).typingBlockedReason)
    }

    @Test("마우스만 죽은 경우 키보드는 막지 않는다")
    func mouseOfflineDoesNotBlockTyping() {
        let keyboardOnly = PiKVMHIDState(
            enabled: true, busy: false, keyboardOnline: true, mouseOnline: false)
        #expect(keyboardOnly.canType)
        #expect(keyboardOnly.typingBlockedReason == nil)
        #expect(keyboardOnly.pointingBlockedReason != nil)
    }
}
