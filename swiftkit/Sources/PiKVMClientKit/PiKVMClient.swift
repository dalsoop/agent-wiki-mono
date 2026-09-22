import Foundation
import HTTPClientKit

/// PiKVM(kvmd) HTTP API 클라이언트.
///
/// 이 타입은 **PiKVM 전용**이다 — generic "KVM 클라이언트" 추상이 아니다. kvmd 고유 사정
/// (`{ok,result}` 봉투, `X-KVMD-*` 헤더 인증, GPIO view 표에서 포트 이름을 읽는 것,
/// 스트리머가 죽으면 nginx 502 가 나오는 것)을 전부 여기 한 곳에 가둔다.
public struct PiKVMClient: Sendable {
    public let endpoint: PiKVMEndpoint
    public let credentials: PiKVMCredentials
    private let http: HTTPClient

    public init(endpoint: PiKVMEndpoint, credentials: PiKVMCredentials, http: HTTPClient? = nil) {
        self.endpoint = endpoint
        self.credentials = credentials
        self.http = http ?? PiKVMTransport(
            trustedSelfSignedHost: endpoint.allowsUntrustedCertificate ? endpoint.host : nil
        )
    }

    // MARK: - 봉투 처리

    /// kvmd 실패 봉투. 성공 봉투와 `result` 모양이 달라 따로 푼다.
    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable {
            let error: String
            let error_msg: String?
        }
        let ok: Bool
        let result: Body
    }

    private struct OKProbe: Decodable {
        let ok: Bool
    }

    /// 봉투를 벗겨 `result` 의 원시 JSON 을 돌려준다.
    private func unwrap(status: Int, data: Data) throws -> Any {
        if status == 401 || status == 403 { throw PiKVMError.unauthorized }

        // kvmd 봉투가 아닌 응답(nginx 502/504 HTML 등)은 HTTP 오류로 올린다 —
        // 하위 데몬이 죽은 상황이라 "해석 실패"보다 이쪽이 정확하다.
        guard let probe = try? JSONDecoder().decode(OKProbe.self, from: data) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary \(data.count)B>"
            throw PiKVMError.http(status: status, body: body)
        }

        if !probe.ok {
            if let env = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                if env.result.error == "UnauthorizedError" || env.result.error == "ForbiddenError" {
                    throw PiKVMError.unauthorized
                }
                throw PiKVMError.api(error: env.result.error, message: env.result.error_msg)
            }
            throw PiKVMError.api(error: "UnknownError", message: nil)
        }

        do {
            guard
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let result = obj["result"]
            else {
                throw PiKVMError.decoding("성공 봉투에 result 가 없다")
            }
            return result
        } catch let err as PiKVMError {
            throw err
        } catch {
            throw PiKVMError.decoding("JSON 파싱 실패: \(error.localizedDescription)")
        }
    }

    private func request(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> Any {
        guard let url = endpoint.url(path: path, query: query) else {
            throw PiKVMError.badRequest("URL 을 만들 수 없다: \(endpoint.host)\(path)")
        }
        var headers = credentials.headers
        if let contentType { headers["Content-Type"] = contentType }
        do {
            let (status, data) = try await http.send(method: method, url: url, headers: headers, body: body)
            return try unwrap(status: status, data: data)
        } catch let error as PiKVMError {
            throw error
        } catch {
            throw PiKVMError.transport(error.localizedDescription)
        }
    }

    /// 바이너리 응답(스냅샷 JPEG). 실패하면 kvmd 봉투를 풀어 오류로 올린다.
    private func requestBinary(_ path: String, query: [String: String] = [:]) async throws -> Data {
        guard let url = endpoint.url(path: path, query: query) else {
            throw PiKVMError.badRequest("URL 을 만들 수 없다: \(endpoint.host)\(path)")
        }
        do {
            let (status, data) = try await http.send(
                method: "GET", url: url, headers: credentials.headers, body: nil
            )
            if status == 200 { return data }
            _ = try unwrap(status: status, data: data)  // 오류 봉투면 여기서 throw
            throw PiKVMError.http(status: status, body: "예상치 못한 응답")
        } catch let error as PiKVMError {
            throw error
        } catch {
            throw PiKVMError.transport(error.localizedDescription)
        }
    }

    // MARK: - 연결 확인

    /// 자격증명이 맞는지만 확인한다. 성공하면 시스템 정보를 함께 돌려준다.
    @discardableResult
    public func verifyConnection() async throws -> PiKVMSystemInfo {
        try await systemInfo()
    }

    // MARK: - /api/info

    public func systemInfo() async throws -> PiKVMSystemInfo {
        let raw = try await request("GET", "/api/info")
        guard let dict = raw as? [String: Any] else {
            throw PiKVMError.decoding("info: 사전이 아니다")
        }
        let system = dict["system"] as? [String: Any] ?? [:]
        let kvmd = system["kvmd"] as? [String: Any] ?? [:]
        let streamer = system["streamer"] as? [String: Any] ?? [:]
        let kernel = system["kernel"] as? [String: Any] ?? [:]
        let hw = dict["hw"] as? [String: Any] ?? [:]
        let health = hw["health"] as? [String: Any] ?? [:]
        let platform = hw["platform"] as? [String: Any] ?? [:]
        let throttling = health["throttling"] as? [String: Any] ?? [:]
        let flags = throttling["parsed_flags"] as? [String: Any] ?? [:]
        let auth = dict["auth"] as? [String: Any] ?? [:]

        func flag(_ name: String, _ when: String) -> Bool {
            ((flags[name] as? [String: Any])?[when] as? Bool) ?? false
        }

        let extras = dict["extras"] as? [String: Any] ?? [:]
        let enabledExtras = extras.compactMap { key, value -> String? in
            guard let v = value as? [String: Any], (v["enabled"] as? Bool) == true else { return nil }
            return key
        }.sorted()

        return PiKVMSystemInfo(
            kvmdVersion: kvmd["version"] as? String ?? "unknown",
            streamerApp: streamer["app"] as? String,
            streamerVersion: streamer["version"] as? String,
            platform: platform["base"] as? String,
            kernelRelease: kernel["release"] as? String,
            authEnabled: auth["enabled"] as? Bool ?? true,
            enabledExtras: enabledExtras,
            metrics: .init(
                cpuTemperatureC: (health["temp"] as? [String: Any])?["cpu"] as? Double,
                cpuPercent: (health["cpu"] as? [String: Any])?["percent"] as? Double,
                memoryPercent: (health["mem"] as? [String: Any])?["percent"] as? Double,
                undervoltageNow: flag("undervoltage", "now"),
                undervoltagePast: flag("undervoltage", "past"),
                throttledNow: flag("throttled", "now"),
                throttledPast: flag("throttled", "past")
            )
        )
    }

    // MARK: - /api/atx (전원)

    public func powerState() async throws -> PiKVMPowerState {
        let raw = try await request("GET", "/api/atx")
        guard let dict = raw as? [String: Any] else {
            throw PiKVMError.decoding("atx: 사전이 아니다")
        }
        let leds = dict["leds"] as? [String: Any] ?? [:]
        return PiKVMPowerState(
            enabled: dict["enabled"] as? Bool ?? false,
            busy: dict["busy"] as? Bool ?? false,
            powerLED: leds["power"] as? Bool ?? false,
            hddLED: leds["hdd"] as? Bool ?? false
        )
    }

    /// ATX 버튼을 누른다. `power_long`·`reset` 은 대상 PC 의 데이터 손실 위험이 있다 —
    /// 호출부가 확인을 받는다(이 계층은 정책을 만들지 않는다).
    public func pressPower(_ action: PiKVMPowerAction) async throws {
        _ = try await request("POST", "/api/atx/click", query: ["button": action.rawValue])
    }

    // MARK: - /api/gpio (KVM 스위치)

    public func switchState() async throws -> PiKVMSwitchState {
        let raw = try await request("GET", "/api/gpio")
        guard let dict = raw as? [String: Any] else {
            throw PiKVMError.decoding("gpio: 사전이 아니다")
        }
        return Self.parseSwitch(gpio: dict)
    }

    /// GPIO 응답에서 포트 목록을 뽑는다.
    ///
    /// 포트 **이름**은 채널 ID(`ch1_button`)가 아니라 kvmd 설정의 표시용 `view.table` 라벨에 있다
    /// ("60 서버" 처럼 사람이 붙인 이름). view 가 없는 설치본을 위해 채널 이름 폴백을 둔다.
    static func parseSwitch(gpio: [String: Any]) -> PiKVMSwitchState {
        let model = gpio["model"] as? [String: Any] ?? [:]
        let scheme = model["scheme"] as? [String: Any] ?? [:]
        let outputs = scheme["outputs"] as? [String: Any] ?? [:]
        let state = gpio["state"] as? [String: Any] ?? [:]
        let inputStates = state["inputs"] as? [String: Any] ?? [:]
        let outputStates = state["outputs"] as? [String: Any] ?? [:]

        let view = model["view"] as? [String: Any]
        let header = view?["header"] as? [String: Any]
        let title = (header?["title"] as? [[String: Any]])?
            .compactMap { $0["text"] as? String }
            .joined(separator: " ")

        var ports: [PiKVMPort] = []
        var claimedOutputs = Set<String>()

        for row in (view?["table"] as? [Any]) ?? [] {
            guard let cells = row as? [Any] else { continue }
            var label: String?
            var ledChannel: String?
            var buttonChannel: String?
            var confirm = false

            for cell in cells {
                guard let c = cell as? [String: Any], let type = c["type"] as? String else { continue }
                switch type {
                case "label":
                    // 행의 첫 라벨이 포트 이름이다.
                    if label == nil { label = c["text"] as? String }
                case "input":
                    if ledChannel == nil { ledChannel = c["channel"] as? String }
                case "output":
                    if buttonChannel == nil {
                        buttonChannel = c["channel"] as? String
                        confirm = c["confirm"] as? Bool ?? false
                    }
                default:
                    break
                }
            }

            guard let button = buttonChannel else { continue }
            claimedOutputs.insert(button)
            let ledState = ledChannel.flatMap { inputStates[$0] as? [String: Any] }
            let outState = outputStates[button] as? [String: Any]
            ports.append(
                PiKVMPort(
                    buttonChannel: button,
                    ledChannel: ledChannel,
                    label: label?.trimmingCharacters(in: .whitespaces).isEmpty == false
                        ? label!.trimmingCharacters(in: .whitespaces)
                        : button,
                    isActive: ledState?["state"] as? Bool ?? false,
                    isOnline: (ledState?["online"] as? Bool) ?? (outState?["online"] as? Bool) ?? true,
                    isBusy: outState?["busy"] as? Bool ?? false,
                    requiresConfirm: confirm
                )
            )
        }

        let others = outputs.keys.filter { !claimedOutputs.contains($0) }.sorted()
        let cleanTitle = title?.trimmingCharacters(in: .whitespaces)
        return PiKVMSwitchState(
            title: (cleanTitle?.isEmpty == false) ? cleanTitle : nil,
            ports: ports,
            otherOutputs: others
        )
    }

    /// 포트를 전환한다 — 스위치 버튼을 짧게 누르는 것(pulse)과 같다.
    public func selectPort(_ port: PiKVMPort) async throws {
        try await pulseChannel(port.buttonChannel)
    }

    public func pulseChannel(_ channel: String) async throws {
        _ = try await request("POST", "/api/gpio/pulse", query: ["channel": channel])
    }

    /// 유지형 GPIO 출력(예: USB 차단기)을 켜고 끈다.
    public func setChannel(_ channel: String, on: Bool) async throws {
        _ = try await request(
            "POST", "/api/gpio/switch", query: ["channel": channel, "state": on ? "1" : "0"]
        )
    }

    // MARK: - /api/msd (가상 미디어)

    public func massStorageState() async throws -> PiKVMMassStorageState {
        let raw = try await request("GET", "/api/msd")
        guard let dict = raw as? [String: Any] else {
            throw PiKVMError.decoding("msd: 사전이 아니다")
        }
        let drive = dict["drive"] as? [String: Any] ?? [:]
        let storage = dict["storage"] as? [String: Any] ?? [:]
        let imagesRaw = storage["images"] as? [String: Any] ?? [:]
        let images = imagesRaw.map { name, value -> PiKVMImage in
            let v = value as? [String: Any] ?? [:]
            return PiKVMImage(
                name: name,
                sizeBytes: (v["size"] as? NSNumber)?.int64Value ?? 0,
                complete: v["complete"] as? Bool ?? true
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        // parts 는 마운트 지점별 용량이다. 기본 파트("")를 쓰고, 없으면 첫 항목.
        let parts = storage["parts"] as? [String: Any] ?? [:]
        let part = (parts[""] as? [String: Any]) ?? (parts.values.first as? [String: Any]) ?? [:]

        return PiKVMMassStorageState(
            enabled: dict["enabled"] as? Bool ?? false,
            online: dict["online"] as? Bool ?? false,
            busy: dict["busy"] as? Bool ?? false,
            connected: drive["connected"] as? Bool ?? false,
            image: drive["image"] as? String,
            isCDROM: drive["cdrom"] as? Bool ?? true,
            isWritable: drive["rw"] as? Bool ?? false,
            volume: .init(
                images: images,
                freeBytes: (part["free"] as? NSNumber)?.int64Value ?? 0,
                totalBytes: (part["size"] as? NSNumber)?.int64Value ?? 0,
                uploading: storage["uploading"] as? String
            )
        )
    }

    /// 붙일 이미지와 모드를 고른다. 대상 PC 에 연결된 상태에서는 kvmd 가 거절한다 —
    /// 먼저 `setMassStorageConnected(false)` 로 떼어야 한다.
    public func selectMassStorageImage(_ name: String, asCDROM: Bool) async throws {
        _ = try await request(
            "POST", "/api/msd/set_params",
            query: ["image": name, "cdrom": asCDROM ? "1" : "0"]
        )
    }

    /// 대상 PC 에 USB 로 붙이거나 뗀다.
    public func setMassStorageConnected(_ connected: Bool) async throws {
        _ = try await request(
            "POST", "/api/msd/set_connected", query: ["connected": connected ? "1" : "0"]
        )
    }

    /// PiKVM 저장소에서 이미지를 지운다.
    public func removeMassStorageImage(_ name: String) async throws {
        _ = try await request("POST", "/api/msd/remove", query: ["image": name])
    }

    /// ISO 를 PiKVM 저장소로 올린다.
    ///
    /// 파일을 스트리밍한다 — 5GB ISO 를 메모리에 올리면 앱이 죽는다. 그래서 이 한 건만
    /// 주입된 `HTTPClient` 를 우회해 전송 계층을 직접 쓴다(전송 계약에 파일 업로드가 없다).
    public func uploadMassStorageImage(
        fileURL: URL,
        name: String? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let imageName = name ?? fileURL.lastPathComponent
        guard let url = endpoint.url(path: "/api/msd/write", query: ["image": imageName]) else {
            throw PiKVMError.badRequest("업로드 URL 을 만들 수 없다")
        }
        let transport = PiKVMTransport(
            trustedSelfSignedHost: endpoint.allowsUntrustedCertificate ? endpoint.host : nil
        )
        let (status, data): (Int, Data)
        do {
            (status, data) = try await transport.upload(
                file: fileURL, to: url, headers: credentials.headers, progress: progress
            )
        } catch {
            throw PiKVMError.transport(error.localizedDescription)
        }
        _ = try unwrap(status: status, data: data)
    }

    // MARK: - /api/hid (키보드·마우스)

    public func hidState() async throws -> PiKVMHIDState {
        let raw = try await request("GET", "/api/hid")
        guard let dict = raw as? [String: Any] else {
            throw PiKVMError.decoding("hid: 사전이 아니다")
        }
        let keyboard = dict["keyboard"] as? [String: Any] ?? [:]
        let mouse = dict["mouse"] as? [String: Any] ?? [:]
        let leds = keyboard["leds"] as? [String: Any] ?? [:]
        let jiggler = dict["jiggler"] as? [String: Any] ?? [:]
        return PiKVMHIDState(
            enabled: dict["enabled"] as? Bool ?? false,
            busy: dict["busy"] as? Bool ?? false,
            connected: dict["connected"] as? Bool,
            keyboardOnline: keyboard["online"] as? Bool ?? false,
            mouseOnline: mouse["online"] as? Bool ?? false,
            mouseAbsolute: mouse["absolute"] as? Bool ?? true,
            indicators: .init(
                capsLock: leds["caps"] as? Bool ?? false,
                numLock: leds["num"] as? Bool ?? false,
                scrollLock: leds["scroll"] as? Bool ?? false,
                jigglerEnabled: jiggler["enabled"] as? Bool ?? false,
                jigglerActive: jiggler["active"] as? Bool ?? false,
                jigglerIntervalSeconds: (jiggler["interval"] as? NSNumber)?.intValue ?? 0
            )
        )
    }

    /// 대상 PC 에 문자열을 타이핑한다. kvmd 가 US 배열 스캔코드로 옮기므로
    /// ASCII 밖 문자(한글 등)는 대상 PC 의 입력기가 아니라 **이 변환**에서 떨어진다.
    public func typeText(_ text: String) async throws {
        _ = try await request(
            "POST", "/api/hid/print",
            query: ["limit": "0"],
            body: Data(text.utf8),
            contentType: "text/plain"
        )
    }

    /// 키 하나를 누른다. 키 이름은 kvmd 규약(웹 `KeyboardEvent.code`) — 예: `Enter`, `Delete`, `F2`.
    public func sendKey(_ key: String) async throws {
        _ = try await request("POST", "/api/hid/events/send_key", query: ["key": key])
    }

    /// USB HID 를 대상 PC 에서 뗐다 붙인다(장치 인식이 꼬였을 때).
    public func resetHID() async throws {
        _ = try await request("POST", "/api/hid/reset")
    }

    /// 마우스 지글러 — 대상 PC 가 화면보호기·절전으로 들어가는 것을 막는다.
    public func setJiggler(enabled: Bool) async throws {
        _ = try await request("POST", "/api/hid/set_params", query: ["jiggler": enabled ? "1" : "0"])
    }

    // MARK: - /api/streamer (영상)

    public func streamerState() async throws -> PiKVMStreamerState {
        let raw = try await request("GET", "/api/streamer")
        guard let dict = raw as? [String: Any] else {
            throw PiKVMError.decoding("streamer: 사전이 아니다")
        }
        let params = dict["params"] as? [String: Any] ?? [:]
        let features = dict["features"] as? [String: Any] ?? [:]
        let limits = dict["limits"] as? [String: Any] ?? [:]
        func range(_ key: String, fallback: ClosedRange<Int>) -> ClosedRange<Int> {
            guard let entry = limits[key] as? [String: Any],
                  let min = (entry["min"] as? NSNumber)?.intValue,
                  let max = (entry["max"] as? NSNumber)?.intValue,
                  min <= max
            else { return fallback }
            return min...max
        }
        // streamer 가 null 이면 ustreamer 프로세스가 안 돌고 있다는 뜻이다.
        let streamer = dict["streamer"] as? [String: Any]
        let source = streamer?["source"] as? [String: Any]
        let resolution = source?["resolution"] as? [String: Any]

        var resolutionText: String?
        if let w = (resolution?["width"] as? NSNumber)?.intValue,
           let h = (resolution?["height"] as? NSNumber)?.intValue {
            resolutionText = "\(w)×\(h)"
        }

        return PiKVMStreamerState(
            running: streamer != nil,
            desiredFPS: (params["desired_fps"] as? NSNumber)?.intValue ?? 0,
            quality: (params["quality"] as? NSNumber)?.intValue,
            h264Bitrate: (params["h264_bitrate"] as? NSNumber)?.intValue,
            supportsH264: features["h264"] as? Bool ?? false,
            capture: .init(
                capturedResolution: resolutionText,
                capturedFPS: (source?["captured_fps"] as? NSNumber)?.intValue,
                hasSignal: source?["online"] as? Bool
            ),
            fpsRange: range("desired_fps", fallback: 0...70),
            qualityRange: range("quality", fallback: 1...100)
        )
    }

    public func setStreamerParams(quality: Int? = nil, desiredFPS: Int? = nil) async throws {
        var query: [String: String] = [:]
        if let quality { query["quality"] = String(quality) }
        if let desiredFPS { query["desired_fps"] = String(desiredFPS) }
        guard !query.isEmpty else { return }
        _ = try await request("POST", "/api/streamer/set_params", query: query)
    }

    /// 현재 화면 한 장(JPEG). 스트리머가 죽어 있으면 kvmd 가 503 을 준다.
    public func snapshotJPEG(allowOffline: Bool = true) async throws -> Data {
        try await requestBinary(
            "/api/streamer/snapshot",
            query: allowOffline ? ["allow_offline": "1"] : [:]
        )
    }

    /// MJPEG 실시간 스트림 URL. `PiKVMVideoStream` 이 이 주소를 읽는다.
    public var streamURL: URL? {
        endpoint.url(path: "/streamer/stream")
    }

    /// 키보드·마우스 이벤트 + 영상 기동용 websocket 주소.
    ///
    /// - Parameter wantsVideo: `stream=1` 로 연다. **이 값이 영상을 켠다** — kvmd 는
    ///   `stream=1` 세션이 있을 때만 ustreamer 를 띄운다. `stream=0` 으로 열면 세션은
    ///   붙지만 영상은 영원히 안 켜진다(2026-08-10 실측으로 밟은 함정).
    public func websocketURL(wantsVideo: Bool) -> URL? {
        guard var c = URLComponents(
            url: endpoint.url(path: "/api/ws", query: ["stream": wantsVideo ? "1" : "0"])
                ?? endpoint.baseURL,
            resolvingAgainstBaseURL: false
        ) else { return nil }
        c.scheme = endpoint.useTLS ? "wss" : "ws"
        return c.url
    }

    /// 이벤트 전용(영상 안 켬) 주소.
    public var websocketURL: URL? { websocketURL(wantsVideo: false) }
}
