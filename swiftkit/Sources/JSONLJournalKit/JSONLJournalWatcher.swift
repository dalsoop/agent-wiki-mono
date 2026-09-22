import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import FastDiskIOKit

/// kqueue 커널 이벤트를 기반으로 파일 끝의 새 라인들을 실시간으로 스트리밍하는 무락(Lock-Free) 관측자.
public final class JSONLJournalWatcher<Record: Codable & Sendable>: Sendable {
    public let journal: JSONLJournal<Record>

    public init(journal: JSONLJournal<Record>) {
        self.journal = journal
    }

    /// 실시간으로 추가되는 새 레코드들을 비동기 스트림으로 제공합니다.
    /// - 현재 파일의 끝(EOF)부터 관측을 시작합니다.
    public func liveTail() -> AsyncStream<Record> {
        AsyncStream(Record.self) { continuation in
            Self.runLiveTail(journal: journal, continuation: continuation)
        }
    }

    private static func runLiveTail(
        journal: JSONLJournal<Record>,
        continuation: AsyncStream<Record>.Continuation
    )
    {
        #if canImport(Darwin)
        runKqueueLiveTail(journal: journal, continuation: continuation)
        #else
        runPollingLiveTail(journal: journal, continuation: continuation)
        #endif
    }

    #if canImport(Darwin)
    private static func runKqueueLiveTail(
        journal: JSONLJournal<Record>,
        continuation: AsyncStream<Record>.Continuation
    )
    {
        let path = journal.path
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = journal.dateCoding.decoderStrategy

        ensureFileExists(at: path)

        let fd = open(journal.path, O_RDONLY | O_NONBLOCK)
        guard fd >= 0 else {
            continuation.finish()
            return
        }

        var lastOffset = Int64(max(0, lseek(fd, 0, SEEK_END)))

        let queue = DispatchQueue(
            label: "com.swiftkit.jsonljournal.watcher.\(UUID().uuidString)",
            qos: .utility
        )
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: queue
        )

        var remainderData = Data()

        source.setEventHandler {
            let data: Data
            let newOffset: Int64
            do {
                (data, newOffset) = try FastFileReader.readAppendChunk(path: path, fromOffset: lastOffset)
            } catch {
                return
            }
            lastOffset = newOffset
            guard !data.isEmpty else { return }
            var buffer = remainderData
            buffer.append(data)
            processBuffer(
                buffer: &buffer,
                remainder: &remainderData,
                decoder: decoder,
                yieldRecord: { continuation.yield($0) }
            )
        }

        source.setCancelHandler {
            close(fd)
        }

        continuation.onTermination = { @Sendable _ in
            source.cancel()
        }

        source.resume()
    }
    #endif

    private static func runPollingLiveTail(
        journal: JSONLJournal<Record>,
        continuation: AsyncStream<Record>.Continuation
    )
    {
        let path = journal.path
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = journal.dateCoding.decoderStrategy
        ensureFileExists(at: path)

        let fd = open(journal.path, O_RDONLY | O_NONBLOCK)
        guard fd >= 0 else {
            continuation.finish()
            return
        }
        var lastOffset = Int64(max(0, lseek(fd, 0, SEEK_END)))
        close(fd)

        let queue = DispatchQueue(
            label: "com.swiftkit.jsonljournal.watcher.poll.\(UUID().uuidString)",
            qos: .utility
        )
        let timer = DispatchSource.makeTimerSource(queue: queue)
        var remainderData = Data()
        timer.schedule(deadline: .now(), repeating: .milliseconds(250))
        timer.setEventHandler {
            consumeAppend(
                path: path,
                lastOffset: &lastOffset,
                remainderData: &remainderData,
                decoder: decoder,
                continuation: continuation
            )
        }
        let holder = TimerHolder(timer)
        continuation.onTermination = { @Sendable _ in
            holder.cancel()
        }
        timer.resume()
    }

    private final class TimerHolder: Sendable {
        private let lock = NSLock()
        private nonisolated(unsafe) var timer: DispatchSourceTimer?

        init(_ timer: DispatchSourceTimer) {
            self.timer = timer
        }

        func cancel() {
            lock.lock()
            let current = timer
            timer = nil
            lock.unlock()
            current?.cancel()
        }
    }

    private static func consumeAppend(
        path: String,
        lastOffset: inout Int64,
        remainderData: inout Data,
        decoder: JSONDecoder,
        continuation: AsyncStream<Record>.Continuation
    )
    {
        let data: Data
        let newOffset: Int64
        do {
            (data, newOffset) = try FastFileReader.readAppendChunk(path: path, fromOffset: lastOffset)
        } catch {
            return
        }
        lastOffset = newOffset
        guard !data.isEmpty else { return }
        var buffer = remainderData
        buffer.append(data)
        processBuffer(
            buffer: &buffer,
            remainder: &remainderData,
            decoder: decoder,
            yieldRecord: { continuation.yield($0) }
        )
    }

    private static func ensureFileExists(at path: String) {
        guard !FileManager.default.fileExists(atPath: path) else { return }
        let parentDir = (path as NSString).deletingLastPathComponent
        guard !parentDir.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        } catch {
            // 디렉터리 생성 실패 시에도 createFile 시도로 에러 상태 위임
            _ = error
        }
        FileManager.default.createFile(atPath: path, contents: Data())
    }

    private static func processBuffer(
        buffer: inout Data,
        remainder: inout Data,
        decoder: JSONDecoder,
        yieldRecord: (Record) -> Void
    ) {
        var startIndex = buffer.startIndex
        while let newlineIndex = buffer[startIndex...].firstIndex(of: 0x0A) {
            let lineRange = startIndex..<newlineIndex
            let lineData = buffer.subdata(in: lineRange)
            startIndex = buffer.index(after: newlineIndex)

            do {
                let record = try decoder.decode(Record.self, from: lineData)
                yieldRecord(record)
            } catch {
                // 불완전하거나 손상된 라인은 방어적으로 건너뜀 (Torn Write 방어)
                _ = error
            }
        }

        guard startIndex < buffer.endIndex else {
            remainder.removeAll(keepingCapacity: true)
            return
        }
        remainder = buffer.subdata(in: startIndex..<buffer.endIndex)
    }
}
