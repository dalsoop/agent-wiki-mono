import Foundation

public struct LogChunk: Sendable, Equatable {
    public let jobID: String
    public let text: String
    public let startOffset: UInt64
    public let endOffset: UInt64
    public let isEOF: Bool
    
    public init(jobID: String, text: String, startOffset: UInt64, endOffset: UInt64, isEOF: Bool) {
        self.jobID = jobID
        self.text = text
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.isEOF = isEOF
    }
}

public protocol LiveLogTailStreaming: Sendable {
    func tailLog(for jobID: String, logPath: String, fromOffset: UInt64) -> AsyncStream<LogChunk>
}

public final class LiveLogTailStreamer: LiveLogTailStreaming, Sendable {
    public static let shared = LiveLogTailStreamer()
    private let queue = DispatchQueue(label: "ai.gujo.awo.log-tailer", qos: .userInitiated)

    public init() {}

    public func tailLog(
        for jobID: String,
        logPath: String,
        fromOffset: UInt64 = 0
    ) -> AsyncStream<LogChunk> {
        return AsyncStream(LogChunk.self) { continuation in
            let fd = open(logPath, O_RDONLY)
            if fd < 0 {
                continuation.finish()
                return
            }
            self.startWatching(fd: fd, jobID: jobID, fromOffset: fromOffset, continuation: continuation)
        }
    }
    
    private func startWatching(
        fd: Int32,
        jobID: String,
        fromOffset: UInt64,
        continuation: AsyncStream<LogChunk>.Continuation
    ) {
        var currentOffset = off_t(fromOffset)
        let fileSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.extend, .write, .delete],
            queue: self.queue
        )

        let reader = { () -> (String, off_t)? in
            Self.readAvailable(fd: fd, currentOffset: &currentOffset)
        }

        self.yieldInitial(jobID: jobID, reader: reader, currentOffset: &currentOffset, continuation: continuation)

        fileSource.setEventHandler {
            if fileSource.data.contains(.delete) {
                fileSource.cancel()
                return
            }
            if let (text, start) = reader() {
                let chunk = LogChunk(jobID: jobID, text: text, startOffset: UInt64(start), endOffset: UInt64(currentOffset), isEOF: false)
                continuation.yield(chunk)
            }
        }

        fileSource.setCancelHandler {
            close(fd)
            continuation.finish()
        }

        continuation.onTermination = { _ in
            fileSource.cancel()
        }

        fileSource.resume()
    }
    
    private func yieldInitial(
        jobID: String,
        reader: () -> (String, off_t)?,
        currentOffset: inout off_t,
        continuation: AsyncStream<LogChunk>.Continuation
    ) {
        if let (initialText, start) = reader() {
            let chunk = LogChunk(
                jobID: jobID,
                text: initialText,
                startOffset: UInt64(start),
                endOffset: UInt64(currentOffset),
                isEOF: false
            )
            continuation.yield(chunk)
        }
    }
    
    private static func readAvailable(fd: Int32, currentOffset: inout off_t) -> (String, off_t)? {
        let end = lseek(fd, 0, SEEK_END)
        guard end > currentOffset else { return nil }
        let length = Int(end - currentOffset)
        lseek(fd, currentOffset, SEEK_SET)

        var buffer = [UInt8](repeating: 0, count: length)
        let bytesRead = read(fd, &buffer, length)
        guard bytesRead > 0 else { return nil }

        let text = String(decoding: buffer[..<bytesRead], as: UTF8.self)
        let start = currentOffset
        currentOffset += off_t(bytesRead)
        return (text, start)
    }
}
