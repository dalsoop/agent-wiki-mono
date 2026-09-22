import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(os)
import os
#endif

/// Unix Domain Socket을 통해 Primary <-> Secondary 프로세스 간 Focus 핸드오프를 수행하는 채널.
public final class InstanceHandoffChannel: Sendable {

    public struct Message: Codable, Sendable {
        public enum Action: String, Codable, Sendable {
            case focus
            case ping
        }
        public let action: Action
        public let senderPID: pid_t
        public let arguments: [String]
        public let timestamp: TimeInterval

        public init(action: Action = .focus, arguments: [String] = CommandLine.arguments) {
            self.action = action
            self.senderPID = getpid()
            self.arguments = arguments
            self.timestamp = Date().timeIntervalSince1970
        }
    }

    public struct Response: Codable, Sendable {
        public let acknowledged: Bool
        public let message: String?

        public init(acknowledged: Bool, message: String? = nil) {
            self.acknowledged = acknowledged
            self.message = message
        }
    }

    #if canImport(os)
    private struct ServerState {
        var source: DispatchSourceRead?
        var fileDescriptor: Int32 = -1
        var isListening = false
    }

    private let socketURL: URL
    private let serverState = OSAllocatedUnfairLock(initialState: ServerState())
    #else
    private let socketURL: URL
    private let stateLock = NSLock()
    private var serverSource: DispatchSourceRead?
    private var serverFD: Int32 = -1
    private var _isListening: Bool = false
    #endif

    public init(socketURL: URL) {
        self.socketURL = socketURL
    }

    // MARK: - Server (Primary)

    /// Primary 인스턴스에서 UDS 소켓을 바인드하고 비동기 수신 대기한다.
    public func startListening(onFocus: @escaping @Sendable (Message) -> Void) -> Bool {
        let path = socketURL.path
        guard path.utf8.count <= InstanceLockScope.maxUDSPathLength else { return false }
        unlink(path)
        guard let fd = makeBoundSocket(path: path) else { return false }
        guard beginListening(fd: fd, path: path) else { return false }
        storeListeningDescriptor(fd)
        let source = makeReadSource(fd: fd, path: path, onFocus: onFocus)
        storeReadSource(source)
        source.resume()
        return true
    }

    private func makeBoundSocket(path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = sockaddr_un()
        #if canImport(Darwin)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPathLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            strncpy(ptr, path, maxPathLen)
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddrPtr in
                #if canImport(Darwin)
                Darwin.bind(fd, sockAddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                #else
                Glibc.bind(fd, sockAddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                #endif
            }
        }
        guard bindResult == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    private func beginListening(fd: Int32, path: String) -> Bool {
        #if canImport(Darwin)
        let listenResult = Darwin.listen(fd, 5)
        #else
        let listenResult = Glibc.listen(fd, 5)
        #endif
        guard listenResult == 0 else {
            close(fd)
            unlink(path)
            return false
        }
        return true
    }

    private func storeListeningDescriptor(_ fd: Int32) {
        #if canImport(os)
        serverState.withLock {
            $0.fileDescriptor = fd
            $0.isListening = true
        }
        #else
        self.serverFD = fd
        stateLock.lock()
        self._isListening = true
        stateLock.unlock()
        #endif
    }

    private func makeReadSource(
        fd: Int32,
        path: String,
        onFocus: @escaping @Sendable (Message) -> Void
    ) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: fd,
            queue: DispatchQueue.global(qos: .userInteractive)
        )
        source.setEventHandler { [weak self] in
            guard let self, let clientFD = self.acceptClient(fd: fd) else { return }
            guard clientFD >= 0 else { return }
            self.handleClient(fd: clientFD, onFocus: onFocus)
        }

        source.setCancelHandler {
            close(fd)
            unlink(path)
        }
        return source
    }

    private func acceptClient(fd: Int32) -> Int32? {
        var clientAddr = sockaddr_un()
        var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                #if canImport(Darwin)
                Darwin.accept(fd, socketAddress, &clientLen)
                #else
                Glibc.accept(fd, socketAddress, &clientLen)
                #endif
            }
        }
        return clientFD >= 0 ? clientFD : nil
    }

    private func storeReadSource(_ source: DispatchSourceRead) {
        #if canImport(os)
        serverState.withLock { $0.source = source }
        #else
        self.serverSource = source
        #endif
    }

    private func handleClient(fd: Int32, onFocus: @Sendable (Message) -> Void) {
        defer { close(fd) }
        var buffer = [UInt8](repeating: 0, count: 4096)
        #if canImport(Darwin)
        let bytesRead = Darwin.read(fd, &buffer, buffer.count)
        #else
        let bytesRead = Glibc.read(fd, &buffer, buffer.count)
        #endif
        guard bytesRead > 0 else { return }

        let data = Data(buffer.prefix(bytesRead))
        if let message = try? JSONDecoder().decode(Message.self, from: data) {
            onFocus(message)
            let response = Response(acknowledged: true, message: "Focus handled")
            if let respData = try? JSONEncoder().encode(response) {
                _ = respData.withUnsafeBytes { ptr in
                    #if canImport(Darwin)
                    Darwin.write(fd, ptr.baseAddress, ptr.count)
                    #else
                    Glibc.write(fd, ptr.baseAddress, ptr.count)
                    #endif
                }
            }
        }
    }

    // MARK: - Client (Secondary)

    /// Secondary 인스턴스에서 Primary의 UDS 소켓으로 Focus 요청을 전송한다.
    public static func sendHandoff(to socketURL: URL, message: Message = Message()) -> Bool {
        let path = socketURL.path
        guard path.utf8.count <= InstanceLockScope.maxUDSPathLength else { return false }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        // 소켓 타임아웃 설정 (500ms)
        var tv = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        #if canImport(Darwin)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPathLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            strncpy(ptr, path, maxPathLen)
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddrPtr in
                #if canImport(Darwin)
                Darwin.connect(fd, sockAddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                #else
                Glibc.connect(fd, sockAddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                #endif
            }
        }
        guard connectResult == 0 else { return false }

        guard let payload = try? JSONEncoder().encode(message) else { return false }
        let written = payload.withUnsafeBytes { ptr in
            #if canImport(Darwin)
            Darwin.write(fd, ptr.baseAddress, ptr.count)
            #else
            Glibc.write(fd, ptr.baseAddress, ptr.count)
            #endif
        }
        guard written == payload.count else { return false }

        // 응답 대기
        var respBuf = [UInt8](repeating: 0, count: 1024)
        #if canImport(Darwin)
        let readBytes = Darwin.read(fd, &respBuf, respBuf.count)
        #else
        let readBytes = Glibc.read(fd, &respBuf, respBuf.count)
        #endif
        guard readBytes > 0 else { return false }

        let respData = Data(respBuf.prefix(readBytes))
        let response = try? JSONDecoder().decode(Response.self, from: respData)
        return response?.acknowledged ?? false
    }

    public func closeChannel() {
        #if canImport(os)
        let source = serverState.withLock { state -> DispatchSourceRead? in
            let source = state.source
            state.source = nil
            state.fileDescriptor = -1
            state.isListening = false
            return source
        }
        source?.cancel()
        #else
        if let source = serverSource {
            source.cancel()
            serverSource = nil
        }
        #endif
    }

    deinit {
        closeChannel()
    }
}
