import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum FastUDSError: Error, Equatable {
    case pathTooLong, socketCreationFailed(Int32), bindFailed(Int32), listenFailed(Int32)
    case connectFailed(Int32), readFailed(Int32), writeFailed(Int32), timeout, connectionClosed, invalidEncoding
}

#if canImport(Glibc)
private let udsStreamType = Int32(SOCK_STREAM.rawValue)
#else
private let udsStreamType = SOCK_STREAM
#endif

private enum FastUDSIO {
    static func send(fd: Int32, data: Data) throws {
        var len = UInt32(data.count).bigEndian
        var packet = Data(bytes: &len, count: 4)
        packet.append(data)
        try packet.withUnsafeBytes { buf in
            var sent = 0
            while sent < buf.count {
                guard let base = buf.baseAddress else { throw FastUDSError.writeFailed(errno) }
                let n = write(fd, base + sent, buf.count - sent)
                if n <= 0 {
                    if errno == EINTR { continue }
                    if errno == EAGAIN || errno == EWOULDBLOCK { throw FastUDSError.timeout }
                    throw FastUDSError.writeFailed(errno)
                }
                sent += n
            }
        }
    }

    static func receive(fd: Int32) throws -> Data {
        let header = try readExact(fd: fd, count: 4)
        let len = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard len > 0 else { return Data() }
        return try readExact(fd: fd, count: Int(len))
    }

    private static func readExact(fd: Int32, count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { buf in
            var recvd = 0
            while recvd < count {
                guard let base = buf.baseAddress else { throw FastUDSError.readFailed(errno) }
                let n = read(fd, base + recvd, count - recvd)
                if n == 0 { throw FastUDSError.connectionClosed }
                if n < 0 {
                    if errno == EINTR { continue }
                    if errno == EAGAIN || errno == EWOULDBLOCK { throw FastUDSError.timeout }
                    throw FastUDSError.readFailed(errno)
                }
                recvd += n
            }
        }
        return data
    }

    static func makeAddr(_ path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw FastUDSError.pathTooLong }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            path.utf8CString.withUnsafeBytes { buf.copyMemory(from: $0) }
        }
        return addr
    }
}

public final class FastUDSServer: @unchecked Sendable {
    public typealias MessageHandler = @Sendable (Data) async throws -> Data
    public let socketPath: String
    private let handler: MessageHandler
    private var serverFd: Int32 = -1
    private var listenTask: Task<Void, Never>?
    private let lock = NSLock()
    private var isRunning = false

    public init(socketPath: String, handler: @escaping MessageHandler) {
        self.socketPath = socketPath
        self.handler = handler
    }

    deinit { stop() }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning else { return }
        unlink(socketPath)
        let fd = socket(AF_UNIX, udsStreamType, 0)
        guard fd >= 0 else { throw FastUDSError.socketCreationFailed(errno) }
        var addr = try FastUDSIO.makeAddr(socketPath)
        let bindRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bindRes == 0 else { close(fd); throw FastUDSError.bindFailed(errno) }
        guard listen(fd, 128) == 0 else { close(fd); throw FastUDSError.listenFailed(errno) }
        serverFd = fd
        isRunning = true
        listenTask = Task.detached { [weak self, fd] in
            while !Task.isCancelled {
                let clientFd = accept(fd, nil, nil)
                guard clientFd >= 0 else { if errno == EINTR { continue }; break }
                let handler = self?.handler
                Task.detached {
                    defer { close(clientFd) }
                    guard let handler else { return }
                    while !Task.isCancelled {
                        do {
                            let req = try FastUDSIO.receive(fd: clientFd)
                            let res = try await handler(req)
                            try FastUDSIO.send(fd: clientFd, data: res)
                        } catch { break }
                    }
                }
            }
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning else { return }
        isRunning = false
        listenTask?.cancel()
        if serverFd >= 0 { close(serverFd); serverFd = -1 }
        unlink(socketPath)
    }
}

public struct FastUDSClient: Sendable {
    public let socketPath: String
    public let timeout: TimeInterval

    public init(socketPath: String, timeout: TimeInterval = 5.0) {
        self.socketPath = socketPath
        self.timeout = timeout
    }

    public func send(data: Data) async throws -> Data {
        let fd = socket(AF_UNIX, udsStreamType, 0)
        guard fd >= 0 else { throw FastUDSError.socketCreationFailed(errno) }
        defer { close(fd) }
        if timeout > 0 {
            let sec = Int(timeout)
            var tv = timeval()
            tv.tv_sec = .init(sec)
            tv.tv_usec = .init((timeout - Double(sec)) * 1_000_000)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        }
        var addr = try FastUDSIO.makeAddr(socketPath)
        let res = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard res == 0 else { throw FastUDSError.connectFailed(errno) }
        try FastUDSIO.send(fd: fd, data: data)
        return try FastUDSIO.receive(fd: fd)
    }

    @discardableResult
    public func send(string: String) async throws -> String {
        guard let reqData = string.data(using: .utf8) else { throw FastUDSError.invalidEncoding }
        let resData = try await send(data: reqData)
        guard let res = String(data: resData, encoding: .utf8) else { throw FastUDSError.invalidEncoding }
        return res
    }
}
