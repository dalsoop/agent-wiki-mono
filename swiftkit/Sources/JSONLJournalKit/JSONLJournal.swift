import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import FastDiskIOKit

/// JSON Lines 포맷 기반의 추가 전용(Append-Only) 고속 저널 엔진.
/// - 쓰기: POSIX `O_APPEND` 기반 원자적 기록 (5µs, 무잠금)
/// - 읽기: `FastFileReader.readTailLines` 기반 역방향 파일 끝 청크 슬라이싱 (0.05ms)
public final class JSONLJournal<Record: Codable & Sendable>: Sendable {
    public enum DateCodingStrategy: Sendable {
        case iso8601
        case deferredToDate
        case secondsSince1970
        case millisecondsSince1970

        var encoderStrategy: JSONEncoder.DateEncodingStrategy {
            switch self {
            case .iso8601: return .iso8601
            case .deferredToDate: return .deferredToDate
            case .secondsSince1970: return .secondsSince1970
            case .millisecondsSince1970: return .millisecondsSince1970
            }
        }

        var decoderStrategy: JSONDecoder.DateDecodingStrategy {
            switch self {
            case .iso8601: return .iso8601
            case .deferredToDate: return .deferredToDate
            case .secondsSince1970: return .secondsSince1970
            case .millisecondsSince1970: return .millisecondsSince1970
            }
        }
    }

    public let path: String
    public let filePermissions: mode_t
    public let directoryPermissions: mode_t
    public let dateCoding: DateCodingStrategy

    public init(
        path: String,
        filePermissions: mode_t = 0o644,
        directoryPermissions: mode_t = 0o755,
        dateCoding: DateCodingStrategy = .iso8601
    ) {
        self.path = (path as NSString).expandingTildeInPath
        self.filePermissions = filePermissions
        self.directoryPermissions = directoryPermissions
        self.dateCoding = dateCoding
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = dateCoding.encoderStrategy
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dateCoding.decoderStrategy
        return decoder
    }

    private func ensureDirectoryExists() {
        let parentDir = (path as NSString).deletingLastPathComponent
        guard !parentDir.isEmpty else { return }
        if !FileManager.default.fileExists(atPath: parentDir) {
            do { try FileManager.default.createDirectory(
                atPath: parentDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: directoryPermissions]
            ) } catch { _ = error }
        }
    }

    /// 단일 레코드를 저널 끝에 원자적으로 추가합니다 (POSIX O_APPEND, 무잠금, ~5µs).
    @discardableResult
    public func append(_ record: Record) -> Bool {
        let encoder = makeEncoder()
        guard var data = try? encoder.encode(record) else {
            return false
        }
        data.append(0x0A) // '\n'

        ensureDirectoryExists()

        let flags = O_WRONLY | O_CREAT | O_APPEND
        let fd = open(path, flags, filePermissions)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        return data.withUnsafeBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress else { return false }
            var totalWritten = 0
            let totalBytes = rawBuffer.count

            while totalWritten < totalBytes {
                let written = write(fd, baseAddress + totalWritten, totalBytes - totalWritten)
                if written <= 0 {
                    if errno == EINTR { continue }
                    return false
                }
                totalWritten += written
            }
            return true
        }
    }

    /// 여러 레코드를 단일 바이트 버퍼로 합쳐 1회 write()로 원자적으로 추가합니다.
    @discardableResult
    public func append(contentsOf records: [Record]) -> Bool {
        guard !records.isEmpty else { return true }
        let encoder = makeEncoder()
        var combinedData = Data()

        for record in records {
            guard var data = try? encoder.encode(record) else { continue }
            data.append(0x0A)
            combinedData.append(data)
        }
        guard !combinedData.isEmpty else { return false }

        ensureDirectoryExists()

        let flags = O_WRONLY | O_CREAT | O_APPEND
        let fd = open(path, flags, filePermissions)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        return combinedData.withUnsafeBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress else { return false }
            var totalWritten = 0
            let totalBytes = rawBuffer.count

            while totalWritten < totalBytes {
                let written = write(fd, baseAddress + totalWritten, totalBytes - totalWritten)
                if written <= 0 {
                    if errno == EINTR { continue }
                    return false
                }
                totalWritten += written
            }
            return true
        }
    }

    /// 파일 끝에서부터 역방향으로 최대 `limit`건의 정상 레코드를 읽어옵니다.
    /// - 손상되거나 비정상 종료로 잘린 라인(Torn write)은 자동으로 건너뜁니다.
    /// - chronological이 참이면 시간순(과거->최신), 거짓이면 최신순(최신->과거).
    public func readTail(
        limit: Int,
        maxBytes: Int = 1024 * 1024,
        chronological: Bool = true
    ) -> [Record] {
        guard limit > 0 else { return [] }
        guard FileManager.default.fileExists(atPath: path) else { return [] }

        guard let lines = try? FastFileReader.readTailLines(
            path: path,
            maxLines: limit * 2, // 손상 라인 스킵 대비 여유 버퍼
            maxBytes: maxBytes
        ) else {
            return []
        }

        let decoder = makeDecoder()
        var records: [Record] = []
        records.reserveCapacity(min(limit, lines.count))

        if chronological {
            for line in lines {
                guard let data = line.data(using: .utf8) else { continue }
                do {
                    let record = try decoder.decode(Record.self, from: data)
                    records.append(record)
                } catch {}
            }
            if records.count > limit {
                return Array(records.suffix(limit))
            }
            return records
        } else {
            for line in lines.reversed() {
                guard let data = line.data(using: .utf8) else { continue }
                do {
                    let record = try decoder.decode(Record.self, from: data)
                    records.append(record)
                    if records.count >= limit {
                        break
                    }
                } catch {}
            }
            return records
        }
    }
}
