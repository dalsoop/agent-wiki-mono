import Foundation

/// Append-only local queue for doctor events (export / future webhook).
public struct DoctorEventQueue: Sendable {
    public let path: String
    private let minSeverity: DoctorSeverity

    public init(
        path: String = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/AppFleetDoctor/events.jsonl"),
        minSeverity: DoctorSeverity = .warn
    ) {
        self.path = path
        self.minSeverity = minSeverity
    }

    public func append(from report: DoctorReport) throws {
        let interesting = report.findings.filter { $0.severity >= minSeverity }
        guard !interesting.isEmpty else { return }
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        var lines = ""
        for f in interesting {
            let data = try enc.encode(f)
            if let s = String(data: data, encoding: .utf8) {
                lines += s + "\n"
            }
        }
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let d = lines.data(using: .utf8) { try handle.write(contentsOf: d) }
        } else {
            try lines.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    public func readAll() throws -> [DoctorFinding] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8), !text.isEmpty else {
            return []
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? dec.decode(DoctorFinding.self, from: data)
        }
    }
}
