import CommandKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import Network

public struct SystemHostResolver: VPNHostResolving, Sendable {
    public init() {}

    public func addresses(
        for host: String
    ) async -> Result<[String], VPNConnectivityFailure> {
        var hints = addrinfo()
        hints.ai_flags = AI_ADDRCONFIG
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var resultPointer: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &resultPointer) == 0,
              let firstResult = resultPointer
        else {
            return .failure(.dnsResolutionFailed)
        }
        defer { freeaddrinfo(firstResult) }

        var addresses: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = firstResult
        while let entry = current {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(
                entry.pointee.ai_addr,
                entry.pointee.ai_addrlen,
                &buffer,
                socklen_t(buffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if status == 0 {
                let bytes = buffer.prefix { $0 != 0 }.map {
                    UInt8(bitPattern: $0)
                }
                let address = String(decoding: bytes, as: UTF8.self)
                if !addresses.contains(address) {
                    addresses.append(address)
                }
            }
            current = entry.pointee.ai_next
        }

        return addresses.isEmpty ? .failure(.dnsResolutionFailed) : .success(addresses)
    }
}

public struct SystemRouteResolver: VPNRouteResolving, Sendable {
    private let runner: any CommandRunning

    public init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func interfaceName(
        to address: String
    ) async -> Result<String, VPNConnectivityFailure> {
        #if os(macOS)
        let result = await runner.run("/sbin/route", ["-n", "get", address])
        if result.exitCode == 127 {
            // Subprocess fork failed (e.g., EBADF after sleep/wake). Fall back to
            // NWConnection-based interface detection instead of giving up entirely.
            if let fallbackInterface = await Self.probeInterface(to: address) {
                return .success(fallbackInterface)
            }
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(
                .diagnosisUnavailable(
                    detail.isEmpty ? "route inspection failed" : detail
                )
            )
        }
        guard result.ok else {
            return .failure(.noRoute)
        }
        guard let interfaceName = Self.parseInterface(result.stdout) else {
            return .failure(
                .diagnosisUnavailable("route output did not include interface")
            )
        }
        return .success(interfaceName)
        #else
        return .failure(.diagnosisUnavailable("route inspection requires macOS"))
        #endif
    }

    static func parseInterface(_ output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces) == "interface"
            else {
                continue
            }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Fallback: use NWConnection to determine the outbound interface when route
    /// subprocess fails (EBADF/fork failure after prolonged uptime or sleep/wake).
    private static func probeInterface(to address: String) async -> String? {
        guard let port = NWEndpoint.Port(rawValue: 1) else { return nil }
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(address),
                port: port,
                using: .udp
            )
            let state = InterfaceProbeState(
                connection: connection,
                continuation: continuation
            )
            connection.pathUpdateHandler = { path in
                if let iface = path.availableInterfaces.first {
                    state.finish(iface.name)
                }
            }
            connection.stateUpdateHandler = { connectionState in
                switch connectionState {
                case .failed, .cancelled:
                    state.finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue.global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                state.finish(nil)
            }
        }
    }
}

private final class InterfaceProbeState: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: NWConnection
    private var continuation: CheckedContinuation<String?, Never>?

    init(connection: NWConnection, continuation: CheckedContinuation<String?, Never>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ result: String?) {
        let pending = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        guard let pending else { return }
        connection.stateUpdateHandler = nil
        connection.pathUpdateHandler = nil
        connection.cancel()
        pending.resume(returning: result)
    }
}

public struct NWConnectionTCPProbe: VPNTCPProbing, Sendable {
    public init() {}

    public func canConnect(
        host: String,
        port: Int,
        timeoutSeconds: Double
    ) async -> Bool {
        guard let rawPort = UInt16(exactly: port),
              let endpointPort = NWEndpoint.Port(rawValue: rawPort)
        else {
            return false
        }

        return await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: endpointPort,
                using: .tcp
            )
            let state = TCPProbeState(
                connection: connection,
                continuation: continuation
            )
            connection.stateUpdateHandler = { connectionState in
                state.handle(connectionState)
            }
            connection.start(queue: DispatchQueue.global(qos: .utility))
            state.scheduleTimeout(seconds: timeoutSeconds)
        }
    }
}

public struct VPNTargetProbe: VPNConnectivityDiagnosing, Sendable {
    private let inventory: any VPNServiceInventoryProviding
    private let resolver: any VPNHostResolving
    private let route: any VPNRouteResolving
    private let tcp: any VPNTCPProbing
    private let timeoutSeconds: Double

    public init(
        inventory: any VPNServiceInventoryProviding = VPNSystemInventory(),
        resolver: any VPNHostResolving = SystemHostResolver(),
        route: any VPNRouteResolving = SystemRouteResolver(),
        tcp: any VPNTCPProbing = NWConnectionTCPProbe(),
        timeoutSeconds: Double = 3
    ) {
        self.inventory = inventory
        self.resolver = resolver
        self.route = route
        self.tcp = tcp
        self.timeoutSeconds = timeoutSeconds
    }

    public func diagnose(_ target: VPNTarget) async -> VPNConnectivityDiagnosis {
        let activeServices = await inventory.services().filter(\.isConnected)

        let resolvedAddresses = await resolver.addresses(for: target.host)
        guard case .success(let addresses) = resolvedAddresses,
              let address = addresses.first
        else {
            let failure = resolvedAddresses.failure ?? .dnsResolutionFailed
            return failureDiagnosis(target: target, failure: failure)
        }

        let resolvedRoute = await route.interfaceName(to: address)
        guard case .success(let interfaceName) = resolvedRoute else {
            let failure = resolvedRoute.failure
                ?? .diagnosisUnavailable("route inspection failed")
            return failureDiagnosis(target: target, failure: failure)
        }

        let path: VPNPath
        if let service = activeServices.first(where: {
            $0.interfaceName == interfaceName
        }) {
            path = .vpn(service: service)
        } else if interfaceName.hasPrefix("utun") {
            path = .unidentifiedTunnel(interface: interfaceName)
        } else {
            path = .direct(interface: interfaceName)
        }

        let reachable = await tcp.canConnect(
            host: address,
            port: target.port,
            timeoutSeconds: timeoutSeconds
        )
        if reachable {
            return VPNConnectivityDiagnosis(
                target: target,
                reachable: true,
                path: path,
                failure: nil,
                checkedAt: Date()
            )
        }

        let failure: VPNConnectivityFailure
        switch path {
        case .vpn, .unidentifiedTunnel:
            failure = .targetDidNotRespond(path: path)
        case .direct where !activeServices.isEmpty:
            failure = .routeDoesNotUseConnectedVPN(activeServices: activeServices)
        case .direct, .unavailable:
            failure = .targetDidNotRespond(path: path)
        }
        return VPNConnectivityDiagnosis(
            target: target,
            reachable: false,
            path: path,
            failure: failure,
            checkedAt: Date()
        )
    }

    private func failureDiagnosis(
        target: VPNTarget,
        failure: VPNConnectivityFailure
    ) -> VPNConnectivityDiagnosis {
        VPNConnectivityDiagnosis(
            target: target,
            reachable: false,
            path: .unavailable,
            failure: failure,
            checkedAt: Date()
        )
    }
}

private final class TCPProbeState: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: NWConnection
    private var continuation: CheckedContinuation<Bool, Never>?

    init(
        connection: NWConnection,
        continuation: CheckedContinuation<Bool, Never>
    ) {
        self.connection = connection
        self.continuation = continuation
    }

    func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            finish(true)
        case .failed, .cancelled:
            finish(false)
        default:
            break
        }
    }

    func scheduleTimeout(seconds: Double) {
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + max(0, seconds)
        ) { [self] in
            finish(false)
        }
    }

    private func finish(_ result: Bool) {
        let pendingContinuation = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        guard let pendingContinuation else {
            return
        }
        connection.stateUpdateHandler = nil
        connection.cancel()
        pendingContinuation.resume(returning: result)
    }
}

private extension Result {
    var failure: Failure? {
        guard case .failure(let error) = self else {
            return nil
        }
        return error
    }
}
