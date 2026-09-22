import EmulatorControlClientKit
import Foundation
import Testing

@Suite("Emulator control HTTP contract", .serialized)
struct EmulatorControlClientTests {
    @Test func instancesUseBearerAndDecodeFleet() async throws {
        let requests = RequestLog()
        EmulatorControlURLProtocol.handler = { request in
            requests.append(request)
            return (200, """
            [{
              "name":"desktop-emu-2",
              "type":"desktop",
              "release":"desktop-emu-2",
              "host":"desktop-emu-2.50.internal.kr",
              "power":"running",
              "ready":true,
              "readinessReason":"DeploymentAvailable",
              "node":"k3s-emul",
              "desiredReplicas":1,
              "managementKind":"helm",
              "pvcs":["desktop-emu-2-config"]
            }]
            """)
        }
        let tokenStore = InMemoryDeviceTokenStore(token: "device-token")
        let client = EmulatorControlClient(
            baseURL: URL(string: "https://emulator-control.test/v1")!,
            session: testSession(),
            tokenStore: tokenStore
        )

        let instances = try await client.instances()

        #expect(instances.map(\.name) == ["desktop-emu-2"])
        #expect(instances.first?.type == .desktop)
        #expect(instances.first?.ready == true)
        #expect(instances.first?.readinessReason == "DeploymentAvailable")
        #expect(requests.paths == ["/v1/instances"])
        #expect(requests.authorizationHeaders == ["Bearer device-token"])
    }

    @Test func readinessReasonIsOptionalForOlderFleetAndConsoleResponses() throws {
        let decoder = JSONDecoder()
        let legacyInstance = try decoder.decode(FleetInstance.self, from: Data("""
        {"name":"browser-emu-1","type":"browser","release":"browser-emu-1",
         "power":"running","ready":false,"desiredReplicas":1,"managementKind":"helm","pvcs":[]}
        """.utf8))
        let console = try decoder.decode(FleetConsole.self, from: Data("""
        {"name":"desktop-emu-1","type":"desktop","url":"https://desktop-emu-1.50.internal.kr/vnc.html",
         "mode":"novnc","readiness":"notReady","readinessReason":"PodCrashLoopBackOff","capabilities":["keyboard"]}
        """.utf8))

        #expect(legacyInstance.readinessReason == nil)
        #expect(console.readinessReason == "PodCrashLoopBackOff")
    }

    @Test func retainedDataUsesBearerAndDecodesPVCMetadata() async throws {
        let requests = RequestLog()
        EmulatorControlURLProtocol.handler = { request in
            requests.append(request)
            return (200, """
            [{
              "name":"desktop-emu-3",
              "type":"desktop",
              "pvcs":[{"name":"desktop-emu-3-home","phase":"Bound","capacity":"20Gi"}]
            }]
            """)
        }
        let client = EmulatorControlClient(
            baseURL: URL(string: "https://emulator-control.test/v1")!,
            session: testSession(),
            tokenStore: InMemoryDeviceTokenStore(token: "device-token")
        )

        let retained = try await client.retainedInstances()

        #expect(retained.map(\.name) == ["desktop-emu-3"])
        #expect(retained.first?.pvcs.first?.capacity == "20Gi")
        #expect(requests.paths == ["/v1/retained"])
        #expect(requests.authorizationHeaders == ["Bearer device-token"])
    }

    @Test func createUsesIdempotencyHeaderAndWireBody() async throws {
        let requests = RequestLog()
        EmulatorControlURLProtocol.handler = { request in
            requests.append(request)
            return (202, """
            {
              "id":"operation-1",
              "kind":"create",
              "instanceName":"browser-emu-2",
              "stage":"finished",
              "status":"completed",
              "createdAt":"2026-07-23T12:00:00.123456789Z",
              "updatedAt":"2026-07-23T12:00:01.987654321Z"
            }
            """)
        }
        let client = EmulatorControlClient(
            baseURL: URL(string: "https://emulator-control.test/v1")!,
            session: testSession(),
            tokenStore: InMemoryDeviceTokenStore(token: "device-token")
        )
        let key = UUID(uuidString: "5D593B03-9F1A-4EBC-863E-4C777538ACB2")!

        let operation = try await client.create(type: .browser, profile: "default", idempotencyKey: key)

        #expect(operation.instanceName == "browser-emu-2")
        #expect(requests.paths == ["/v1/instances"])
        #expect(requests.idempotencyHeaders == [key.uuidString])
        #expect(requests.bodies.first == #"{"profile":"default","size":"standard","type":"browser"}"#)
    }

    @Test func actionRemovePurgeAndOperationUseDocumentedPaths() async throws {
        let requests = RequestLog()
        EmulatorControlURLProtocol.handler = { request in
            requests.append(request)
            if request.url?.path.hasSuffix("/operations/operation-1") == true {
                return (200, operationJSON)
            }
            return (202, operationJSON)
        }
        let client = EmulatorControlClient(
            baseURL: URL(string: "https://emulator-control.test/v1")!,
            session: testSession(),
            tokenStore: InMemoryDeviceTokenStore(token: "device-token")
        )

        _ = try await client.act(.restart, on: "desktop-emu-2", idempotencyKey: UUID())
        _ = try await client.remove(name: "desktop-emu-2", idempotencyKey: UUID())
        _ = try await client.purge(
            name: "desktop-emu-2",
            confirmation: "desktop-emu-2",
            idempotencyKey: UUID()
        )
        _ = try await client.operation(id: "operation-1")

        #expect(requests.paths == [
            "/v1/instances/desktop-emu-2/actions/restart",
            "/v1/instances/desktop-emu-2",
            "/v1/retained/desktop-emu-2/purge",
            "/v1/operations/operation-1",
        ])
        #expect(requests.methods == ["POST", "DELETE", "POST", "GET"])
    }

    @Test func agentJobsDispatchAndDecodeWorkerState() async throws {
        let requests = RequestLog()
        let jobJSON = """
        {
          "id":"3e87a243-ba73-499a-be8e-2c3431b6cb32",
          "state":"queued",
          "spec":{
            "title":"inspect logs",
            "prompt":"Reply with exactly OK.",
            "workdir":"/config",
            "worker":"codex",
            "model":"gemini-2.5-flash-emulator-fallback",
            "effort":"low",
            "timeoutMinutes":3,
            "isolation":"forbid-worktree",
            "allowedPaths":[],
            "forbiddenPaths":["/config/.ssh"]
          },
          "createdAt":"2026-08-01T07:17:57Z"
        }
        """
        let responseOperationJSON = operationJSON
        EmulatorControlURLProtocol.handler = { request in
            requests.append(request)
            switch request.url?.path {
            case "/v1/instances/desktop-emu-2/agent-jobs":
                if request.httpMethod == "POST" {
                    return (201, "{\"operation\":\(responseOperationJSON),\"job\":\(jobJSON)}")
                }
                return (200, "[\(jobJSON)]")
            case "/v1/instances/desktop-emu-2/agent-jobs/3e87a243-ba73-499a-be8e-2c3431b6cb32":
                return (200, jobJSON)
            default:
                return (404, "{}")
            }
        }
        let client = EmulatorControlClient(
            baseURL: URL(string: "https://emulator-control.test/v1")!,
            session: testSession(),
            tokenStore: InMemoryDeviceTokenStore(token: "device-token")
        )
        let key = UUID(uuidString: "5D593B03-9F1A-4EBC-863E-4C777538ACB2")!

        let dispatched = try await client.dispatchAgentJob(
            on: "desktop-emu-2",
            request: FleetAgentJobRequest(
                title: "inspect logs",
                prompt: "Reply with exactly OK.",
                workdir: "/config",
                effort: .low,
                timeoutMinutes: 3
            ),
            idempotencyKey: key
        )
        let listed = try await client.agentJobs(on: "desktop-emu-2")
        let job = try await client.agentJob(on: "desktop-emu-2", id: "3e87a243-ba73-499a-be8e-2c3431b6cb32")

        #expect(dispatched.operation.id == "operation-1")
        #expect(dispatched.job?.spec.model == "gemini-2.5-flash-emulator-fallback")
        #expect(listed.map(\.id) == ["3e87a243-ba73-499a-be8e-2c3431b6cb32"])
        #expect(listed[0].changedFiles.isEmpty)
        #expect(job.scopeViolations.isEmpty)
        #expect(requests.paths == [
            "/v1/instances/desktop-emu-2/agent-jobs",
            "/v1/instances/desktop-emu-2/agent-jobs",
            "/v1/instances/desktop-emu-2/agent-jobs/3e87a243-ba73-499a-be8e-2c3431b6cb32",
        ])
        #expect(requests.idempotencyHeaders == [key.uuidString])
        #expect(requests.bodies.first?.contains("\"model\"") == false)
        #expect(requests.bodies.first?.contains("\"effort\":\"low\"") == true)
    }

    @Test func pairStoresReturnedToken() async throws {
        EmulatorControlURLProtocol.handler = { _ in
            (201, #"{"token":"paired-token","expiresAt":"2026-08-23T12:00:00Z"}"#)
        }
        let store = InMemoryDeviceTokenStore()
        let client = EmulatorControlClient(
            baseURL: URL(string: "https://emulator-control.test/v1")!,
            session: testSession(),
            tokenStore: store
        )

        let pairing = try await client.pair(code: "123456", deviceName: "iPhone")

        #expect(pairing.expiresAt > Date(timeIntervalSince1970: 0))
        #expect(await store.loadToken() == "paired-token")
    }

    @Test func unauthorizedIsTypedAndErrorsNeverContainToken() async {
        EmulatorControlURLProtocol.handler = { _ in (401, #"{"error":"device-token rejected"}"#) }
        let client = EmulatorControlClient(
            baseURL: URL(string: "https://emulator-control.test/v1")!,
            session: testSession(),
            tokenStore: InMemoryDeviceTokenStore(token: "device-token")
        )

        do {
            _ = try await client.instances()
            Issue.record("expected unauthorized")
        } catch {
            #expect(error as? EmulatorControlError == .unauthorized)
            #expect(!String(describing: error).contains("device-token"))
        }
    }

    private func testSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EmulatorControlURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private var operationJSON: String {
        """
        {
          "id":"operation-1",
          "kind":"restart",
          "instanceName":"desktop-emu-2",
          "stage":"finished",
          "status":"completed",
          "createdAt":"2026-07-23T12:00:00Z",
          "updatedAt":"2026-07-23T12:00:01Z"
        }
        """
    }
}

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var capturedBodies: [String] = []

    func append(_ request: URLRequest) {
        let body = Self.body(from: request)
        lock.withLock {
            requests.append(request)
            if let body {
                capturedBodies.append(body)
            }
        }
    }

    var paths: [String] {
        lock.withLock { requests.compactMap(\.url?.path) }
    }

    var methods: [String] {
        lock.withLock { requests.compactMap(\.httpMethod) }
    }

    var authorizationHeaders: [String] {
        lock.withLock { requests.compactMap { $0.value(forHTTPHeaderField: "Authorization") } }
    }

    var idempotencyHeaders: [String] {
        lock.withLock { requests.compactMap { $0.value(forHTTPHeaderField: "Idempotency-Key") } }
    }

    var bodies: [String] {
        lock.withLock { capturedBodies }
    }

    private static func body(from request: URLRequest) -> String? {
        if let data = request.httpBody {
            return String(data: data, encoding: .utf8)
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8)
    }
}

private final class EmulatorControlURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: @Sendable (URLRequest) -> (Int, String) = { _ in (500, "{}") }

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = Self.handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
