import Foundation

// MARK: - Video generation request / job types

/// A video-generation job request submitted through the panel video API.
/// The canonical ComfyUI workflow template lives on the host; the app sends
/// only these parameters and the panel fills the template + round-robins.
public struct VideoGenerationRequest: Codable, Sendable, Equatable {
    public var prompt: String
    public var width: Int
    public var height: Int
    public var duration: Int
    /// "auto" for round-robin to a healthy/idle instance, else "0".."3".
    public var instance: String

    public init(prompt: String, width: Int = 832, height: Int = 480, duration: Int = 5, instance: String = "auto") {
        self.prompt = prompt
        self.width = width
        self.height = height
        self.duration = duration
        self.instance = instance
    }
}

public enum VideoJobState: String, Codable, Sendable, Equatable {
    case queued
    case running
    case done
    case error
    case unknown
}

public struct VideoJobOutput: Codable, Sendable, Equatable {
    public let filename: String
    public let url: String

    public init(filename: String, url: String) {
        self.filename = filename
        self.url = url
    }
}

public struct VideoJob: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let instance: Int
    public var state: VideoJobState
    /// 0...1; -1 means unknown.
    public var progress: Double
    public var outputs: [VideoJobOutput]
    public var detail: String?

    public init(id: String, instance: Int, state: VideoJobState, progress: Double = 0, outputs: [VideoJobOutput] = [], detail: String? = nil) {
        self.id = id
        self.instance = instance
        self.state = state
        self.progress = progress
        self.outputs = outputs
        self.detail = detail
    }

    public var isTerminal: Bool { state == .done || state == .error }
    public var progressFraction: Double { max(0, min(1, progress)) }
}

// MARK: - Client

public enum VideoJobClientError: Error, Equatable, LocalizedError, Sendable {
    case invalidURL(String)
    case httpStatus(Int, String)
    case decode(String)
    case transport(String)
    /// 401/403 — 공개 도메인 앞단의 basic-auth 가 막았다. "서버가 죽었다"와
    /// 구분해야 설정 화면이 자격 입력을 안내할 수 있다.
    case unauthorized(Int)

    public var errorDescription: String? {
        switch self {
        case .unauthorized(let code):
            return "패널 인증 실패(HTTP \(code)) — 설정에서 계정·비밀번호를 확인하세요."
        case .invalidURL(let s): return "invalid video API URL: \(s)"
        case .httpStatus(let code, let body):
            let short = body.count > 240 ? String(body.prefix(240)) + "…" : body
            return "video API HTTP \(code): \(short.isEmpty ? "(empty body)" : short)"
        case .decode(let m): return "video API decode failed: \(m)"
        case .transport(let m): return "video API transport: \(m)"
        }
    }
}

/// Fronts the panel's video-generation API (which itself fronts ComfyUI with
/// round-robin + health). The app never talks to ComfyUI directly.
public protocol VideoJobClienting: Sendable {
    func submit(baseURL: String, request: VideoGenerationRequest) async throws -> VideoJob
    func status(baseURL: String, jobID: String) async throws -> VideoJob
    func jobs(baseURL: String) async throws -> [VideoJob]
    func fetchURL(baseURL: String, jobID: String) -> URL?
    /// 다운로드·재생(AVURLAsset)에 실어야 할 추가 헤더. 인증이 걸린 공개 도메인에서
    /// `fetchURL` 만으로는 401 이 나므로 소비자가 이 헤더를 함께 준다.
    func fetchHeaders(baseURL: String) -> [String: String]
}

extension VideoJobClienting {
    /// 기본은 헤더 없음 — 내부망 직결 구현·테스트 목이 그대로 통과한다.
    public func fetchHeaders(baseURL: String) -> [String: String] { [:] }
}

public struct VideoJobList: Codable, Sendable, Equatable {
    public let jobs: [VideoJob]
    public let queued: [String]

    public init(jobs: [VideoJob], queued: [String]) {
        self.jobs = jobs
        self.queued = queued
    }
}

// MARK: - Upscale

/// 업스케일 목표 해상도. H3 native(~1MP) 생성물을 이 타깃의 긴 변까지 키운다.
/// 4K native 는 비현실적(≈16× 픽셀, VRAM·시간)이라 업스케일이 실질 경로다.
public enum UpscaleTarget: String, Codable, Sendable, CaseIterable, Identifiable {
    /// 긴 변 1920 (풀HD).
    case fhd = "1080p"
    /// 긴 변 3840 (UHD 4K).
    case uhd4k = "4k"

    public var id: String { rawValue }
    /// 타깃 긴 변 픽셀.
    public var longEdge: Int {
        switch self { case .fhd: return 1920; case .uhd4k: return 3840 }
    }
    public var label: String { rawValue == "4k" ? "4K" : "1080p" }
}

/// 업스케일 요청 본문 — 소스 잡 id 와 타깃. 패널이 같은 직렬 큐에 업스케일 잡을 넣는다.
public struct VideoUpscaleRequest: Codable, Sendable {
    public let source: String
    public let target: String

    public init(source: String, target: UpscaleTarget) {
        self.source = source
        self.target = target.rawValue
    }
}

/// 업스케일 클라이언트 표면. 생성(`VideoJobClienting`)과 분리한 스튜디오 전용 계약 —
/// 운영 앱(gpu-server-manager)은 이 표면을 참조하지 않아 프로토콜 확장 영향이 0다.
public protocol VideoUpscaleClient: Sendable {
    /// 소스 잡의 완성 영상을 타깃 해상도로 키우는 잡을 제출. 반환값은 업스케일 잡(새 id).
    func upscale(baseURL: String, jobID: String, target: UpscaleTarget) async throws -> VideoJob
}

extension URLSessionVideoJobClient: VideoUpscaleClient {
    public func upscale(baseURL: String, jobID: String, target: UpscaleTarget) async throws -> VideoJob {
        let body = try JSONEncoder().encode(VideoUpscaleRequest(source: jobID, target: target))
        let data = try await send(baseURL: baseURL, path: "/api/video/upscale/\(encode(jobID))", method: "POST", body: body)
        return try decode(VideoJob.self, from: data)
    }
}

public struct URLSessionVideoJobClient: VideoJobClienting {
    private let session: URLSession
    private let timeout: TimeInterval
    /// 공개 도메인(traefik basic-auth) 앞단을 지날 때 붙일 자격. nil 이면 무인증.
    private let credentials: (any PanelCredentialProviding)?

    public init(
        session: URLSession = .shared,
        timeout: TimeInterval = 30,
        credentials: (any PanelCredentialProviding)? = nil
    ) {
        self.session = session
        self.timeout = timeout
        self.credentials = credentials
    }

    public func fetchHeaders(baseURL: String) -> [String: String] {
        guard let c = credentials?.credential(for: GpuPanel.normalize(baseURL)) else { return [:] }
        return ["Authorization": c.authorizationHeaderValue]
    }

    public func submit(baseURL: String, request: VideoGenerationRequest) async throws -> VideoJob {
        let body = try JSONEncoder().encode(request)
        let data = try await send(baseURL: baseURL, path: "/api/video/submit", method: "POST", body: body)
        return try decode(VideoJob.self, from: data)
    }

    public func status(baseURL: String, jobID: String) async throws -> VideoJob {
        let data = try await send(baseURL: baseURL, path: "/api/video/status/\(encode(jobID))", method: "GET", body: nil)
        return try decode(VideoJob.self, from: data)
    }

    public func jobs(baseURL: String) async throws -> [VideoJob] {
        let data = try await send(baseURL: baseURL, path: "/api/video/jobs", method: "GET", body: nil)
        return try decode(VideoJobList.self, from: data).jobs
    }

    public func fetchURL(baseURL: String, jobID: String) -> URL? {
        URL(string: GpuPanel.normalize(baseURL) + "/api/video/fetch/\(encode(jobID))")
    }

    // MARK: - Private

    private func send(baseURL: String, path: String, method: String, body: Data?) async throws -> Data {
        let urlString = GpuPanel.normalize(baseURL) + path
        guard let url = URL(string: urlString) else {
            throw VideoJobClientError.invalidURL(urlString)
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in fetchHeaders(baseURL: baseURL) {
            req.setValue(v, forHTTPHeaderField: k)
        }
        if let body {
            req.httpMethod = method
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        do {
            let (data, response) = try await session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if (200..<300).contains(code) { return data }
            if code == 401 || code == 403 { throw VideoJobClientError.unauthorized(code) }
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            do {
                if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = obj["detail"] as? String {
                    throw VideoJobClientError.httpStatus(code, detail)
                }
            } catch let err as VideoJobClientError {
                throw err
            } catch {
                // JSON parsing failed, fallback to bodyStr
            }
            throw VideoJobClientError.httpStatus(code, bodyStr)
        } catch let e as VideoJobClientError {
            throw e
        } catch {
            throw VideoJobClientError.transport(error.localizedDescription)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw VideoJobClientError.decode(String(describing: error)) }
    }

    private func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }
}
