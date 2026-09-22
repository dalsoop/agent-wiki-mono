import Foundation

/// 최소 HTTP POST 추상(테스트 목킹용). ImageBackend 가 프로세스 대신 HTTP API 를 부를 때 쓴다.
public protocol HTTPPosting: Sendable {
    /// 반환: (본문 데이터, HTTP 상태코드).
    func post(url: URL, headers: [String: String], body: Data, timeout: TimeInterval) async throws -> (Data, Int)
}

/// URLSession 기반 기본 구현.
public struct URLSessionHTTP: HTTPPosting {
    public init() {}
    public func post(url: URL, headers: [String: String], body: Data, timeout: TimeInterval) async throws -> (Data, Int) {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.httpBody = body
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        return (data, code)
    }
}

/// Retro Diffusion(`api.retrodiffusion.ai`) 시트 전용 픽셀아트 모델 백엔드.
///
/// 범용 gpt-image(codex/god-tibo)와 달리 **스프라이트 시트 학습 모델**이라 프레임 간 캐릭터
/// 정체성 일관성이 강하다(2026 벤치: 전용모델 > 범용). `reference_images` 로 캐논 참조,
/// `frames_duration` 으로 애니 프레임을 모델이 직접 배치한다.
///
/// 인증: `X-RD-Token` 헤더. **키는 이 어댑터 밖(env `RETRODIFFUSION_API_KEY`)에서 주입** —
/// 레지스트리·설정에 원문 저장 안 함(워크스페이스 secret 규칙). 유료 API(호출당 과금).
public struct RetroDiffusionBackend: ImageBackend {
    public let id = "retro-diffusion"

    let apiKey: String
    let promptStyle: String
    let baseURL: URL
    let http: HTTPPosting

    public init(apiKey: String,
                promptStyle: String = "rd_plus__default",
                baseURL: URL = URL(string: "https://api.retrodiffusion.ai/v1")!,
                http: HTTPPosting = URLSessionHTTP()) {
        self.apiKey = apiKey
        self.promptStyle = promptStyle
        self.baseURL = baseURL
        self.http = http
    }

    /// 유효한 애니 프레임 값으로 스냅(API 허용: 4,6,8,10,12,16). 범위 밖이면 nil(정지 이미지).
    static func snappedFrames(_ frames: Int?) -> Int? {
        guard let f = frames, f >= 2 else { return nil }
        let allowed = [4, 6, 8, 10, 12, 16]
        return allowed.min(by: { abs($0 - f) < abs($1 - f) })
    }

    /// 요청 JSON 본문을 만든다(테스트가 직접 검증할 수 있게 분리).
    func requestBody(for request: ImageBackendRequest) -> Data {
        var obj: [String: Any] = [
            "prompt": request.basePrompt,
            "prompt_style": promptStyle,
            "width": request.width ?? 256,
            "height": request.height ?? 256,
            "num_images": 1,
        ]
        if let frames = Self.snappedFrames(request.frames) {
            obj["frames_duration"] = frames
        }
        if let canon = request.canonPath {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: canon))
                obj["reference_images"] = [data.base64EncodedString()]
            } catch {}
        }
        do {
            return try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        } catch {
            return Data()
        }
    }

    public func produce(_ request: ImageBackendRequest) async -> ProcessOutcome {
        let url = baseURL.appendingPathComponent("inferences")
        let headers = ["Content-Type": "application/json", "X-RD-Token": apiKey]
        let body = requestBody(for: request)
        do {
            let (data, code) = try await http.post(url: url, headers: headers, body: body, timeout: request.timeout)
            guard code == 200 else {
                let msg = String(data: data, encoding: .utf8) ?? ""
                return ProcessOutcome(stdout: "", stderr: "retro-diffusion HTTP \(code): \(msg.prefix(500))", exitCode: Int32(code))
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let images = json["base64_images"] as? [String],
                  let first = images.first,
                  let png = Data(base64Encoded: first) else {
                return ProcessOutcome(stdout: "", stderr: "retro-diffusion: base64_images 파싱 실패", exitCode: 65)
            }
            try png.write(to: URL(fileURLWithPath: request.outputPath), options: [.atomic])
            return ProcessOutcome(stdout: "ok", stderr: "", exitCode: 0)
        } catch {
            return ProcessOutcome(stdout: "", stderr: "retro-diffusion 요청 실패: \(error.localizedDescription)", exitCode: 1)
        }
    }
}
