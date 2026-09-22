import Foundation

/// 한 번의 생성 시도 기록(재현·감사용).
public struct GenRecord: Codable, Sendable, Equatable {
    public struct Identity: Sendable, Equatable {
        public var timestamp: String
        public var spriteName: String
        public var motion: String
        public var frames: Int

        public init(timestamp: String, spriteName: String, motion: String, frames: Int) {
            self.timestamp = timestamp
            self.spriteName = spriteName
            self.motion = motion
            self.frames = frames
        }
    }

    public struct Paths: Sendable, Equatable {
        public var canon: String
        public var prompt: String
        public var outputPath: String

        public init(canon: String, prompt: String, outputPath: String) {
            self.canon = canon
            self.prompt = prompt
            self.outputPath = outputPath
        }
    }

    public var timestamp: String
    public var spriteName: String
    public var motion: String
    public var frames: Int
    public var canon: String
    public var prompt: String
    public var outputPath: String
    public var ok: Bool
    public var exitCode: Int32

    public init(identity: Identity, paths: Paths, ok: Bool, exitCode: Int32) {
        self.timestamp = identity.timestamp
        self.spriteName = identity.spriteName
        self.motion = identity.motion
        self.frames = identity.frames
        self.canon = paths.canon
        self.prompt = paths.prompt
        self.outputPath = paths.outputPath
        self.ok = ok
        self.exitCode = exitCode
    }
}

/// 생성 이력을 JSONL 로 append 한다. 프롬프트·시각·결과를 남겨 재현·재생성 판단에 쓴다.
public struct GenHistory: Sendable {
    public let path: String
    public init(path: String) { self.path = path }

    public func append(_ record: GenRecord) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        var line = String(data: try enc.encode(record), encoding: .utf8) ?? "{}"
        line += "\n"
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            do {
                let handle = try FileHandle(forWritingTo: url)
                defer { do { try handle.close() } catch {} }
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                return
            } catch {}
        }
        try line.data(using: .utf8)?.write(to: url)
    }
}
