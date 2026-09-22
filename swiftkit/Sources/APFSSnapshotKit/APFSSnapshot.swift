import Foundation
import os

private let logger = Logger(subsystem: "net.ranode.swiftkit", category: "apfs-snapshot")

/// APFS 로컬 스냅샷 정보
public struct APFSSnapshot: Sendable, Equatable, Hashable, Identifiable {
    public var id: String { name }
    
    /// 스냅샷 전체 이름 (예: com.apple.TimeMachine.2026-09-07-200714.local)
    public let name: String
    
    /// 스냅샷 일자 문자열 (예: 2026-09-07-200714)
    public let dateString: String
    
    /// 파싱된 스냅샷 일자 (해석 실패 시 nil)
    public let date: Date?
    
    /// 스냅샷이 생성된 대상 APFS 볼륨 경로 (예: /System/Volumes/Data 또는 /)
    public let volumePath: String
    
    /// 스냅샷 대상 BSD 디바이스 노드 (예: /dev/disk3s5)
    public let deviceNode: String?

    public init(
        name: String,
        dateString: String,
        date: Date? = nil,
        volumePath: String,
        deviceNode: String? = nil
    ) {
        self.name = name
        self.dateString = dateString
        self.date = date ?? APFSSnapshotParser.parseDate(from: dateString)
        self.volumePath = volumePath
        self.deviceNode = deviceNode
    }
}

/// APFS 볼륨 정보
public struct APFSVolumeInfo: Sendable, Equatable {
    public let volumePath: String
    public let deviceNode: String
    public let fileSystemType: String
    public let isAPFS: Bool

    public init(
        volumePath: String,
        deviceNode: String,
        fileSystemType: String,
        isAPFS: Bool
    ) {
        self.volumePath = volumePath
        self.deviceNode = deviceNode
        self.fileSystemType = fileSystemType
        self.isAPFS = isAPFS
    }
}

/// APFS 볼륨 판별 및 BSD 디바이스 노드 추출기 (Darwin statfs API 기반)
public enum APFSVolumeDetector: Sendable {
    /// 지정된 파일/디렉터리가 위치한 마운트 지점의 파일시스템 및 BSD 디바이스 정보를 감지
    public static func detectVolume(for url: URL) throws -> APFSVolumeInfo {
        let path = (url.path as NSString).standardizingPath
        var stat = statfs()
        let ret = statfs(path, &stat)
        guard ret == 0 else {
            let err = errno
            throw APFSSnapshotError.volumeDetectionFailed("statfs failed for '\(path)' with errno \(err)")
        }

        let fsType = withUnsafePointer(to: &stat.f_fstypename) { ptr -> String in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                String(cString: $0)
            }
        }

        let deviceNode = withUnsafePointer(to: &stat.f_mntfromname) { ptr -> String in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                String(cString: $0)
            }
        }

        let mountPoint = withUnsafePointer(to: &stat.f_mntonname) { ptr -> String in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                String(cString: $0)
            }
        }

        let isAPFS = fsType.lowercased() == "apfs"

        return APFSVolumeInfo(
            volumePath: mountPoint,
            deviceNode: deviceNode,
            fileSystemType: fsType,
            isAPFS: isAPFS
        )
    }
}

/// APFS 스냅샷 문자열 파서
public enum APFSSnapshotParser: Sendable {
    private static let standardDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    nonisolated(unsafe) private static let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter
    }()

    /// "2026-09-07-200714" 날짜 문자열 파싱
    public static func parseDate(from dateString: String) -> Date? {
        if let date = standardDateFormatter.date(from: dateString) {
            return date
        }
        return isoDateFormatter.date(from: dateString)
    }

    /// tmutil localsnapshot 실행 출력에서 생성된 스냅샷 파싱
    /// 표준 출력 예:
    /// "Created local snapshot with date: 2026-09-07-200714"
    public static func parseCreatedSnapshot(
        from output: String,
        volumePath: String,
        deviceNode: String? = nil
    ) throws -> APFSSnapshot {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        for line in trimmed.components(separatedBy: .newlines) {
            let lineTrimmed = line.trimmingCharacters(in: .whitespaces)
            if let range = lineTrimmed.range(of: "Created local snapshot with date:") {
                let datePart = String(lineTrimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                let name = "com.apple.TimeMachine.\(datePart).local"
                return APFSSnapshot(
                    name: name,
                    dateString: datePart,
                    volumePath: volumePath,
                    deviceNode: deviceNode
                )
            } else if let range = lineTrimmed.range(of: "Created local snapshot '") {
                let rest = String(lineTrimmed[range.upperBound...])
                if let endQuote = rest.firstIndex(of: "'") {
                    let snapshotName = String(rest[..<endQuote])
                    let datePart = extractDatePart(from: snapshotName) ?? snapshotName
                    return APFSSnapshot(
                        name: snapshotName,
                        dateString: datePart,
                        volumePath: volumePath,
                        deviceNode: deviceNode
                    )
                }
            }
        }
        throw APFSSnapshotError.snapshotCreationFailed("Failed to parse snapshot creation output: '\(output)'")
    }

    /// tmutil listlocalsnapshots 출력 파싱
    /// 출력 예:
    /// Snapshots for volume group containing disk /:
    /// com.apple.TimeMachine.2026-09-07-200714.local
    /// com.apple.TimeMachine.2026-09-07-210000.local
    public static func parseSnapshotList(
        from output: String,
        volumePath: String,
        deviceNode: String? = nil
    ) -> [APFSSnapshot] {
        var results: [APFSSnapshot] = []
        let lines = output.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            guard !line.hasPrefix("Snapshots for") && !line.hasPrefix("Snapshot dates for") else { continue }

            // 1) 전체 이름: com.apple.TimeMachine.2026-09-07-200714.local
            if line.contains("com.apple.TimeMachine.") {
                let name = line
                let datePart = extractDatePart(from: name) ?? name
                results.append(APFSSnapshot(
                    name: name,
                    dateString: datePart,
                    volumePath: volumePath,
                    deviceNode: deviceNode
                ))
            }
            // 2) 날짜만 출력된 경우: 2026-09-07-200714
            else if line.range(of: #"^\d{4}-\d{2}-\d{2}-\d{6}$"#, options: .regularExpression) != nil {
                let name = "com.apple.TimeMachine.\(line).local"
                results.append(APFSSnapshot(
                    name: name,
                    dateString: line,
                    volumePath: volumePath,
                    deviceNode: deviceNode
                ))
            }
        }
        return results
    }

    /// 스냅샷 이름에서 일자 부분 추출
    /// com.apple.TimeMachine.2026-09-07-200714.local -> 2026-09-07-200714
    public static func extractDatePart(from snapshotName: String) -> String? {
        let pattern = #"(\d{4}-\d{2}-\d{2}-\d{6})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(snapshotName.startIndex..<snapshotName.endIndex, in: snapshotName)
        if let match = regex.firstMatch(in: snapshotName, range: range),
           let matchRange = Range(match.range(at: 1), in: snapshotName) {
            return String(snapshotName[matchRange])
        }
        return nil
    }
}
