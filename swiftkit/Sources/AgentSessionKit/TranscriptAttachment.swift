import Foundation

enum TranscriptAttachment {
    static func ingest(
        _ d: [String: Any],
        at: Date?,
        into sink: inout TranscriptSink
    ) -> Bool {
        guard d["type"] as? String == "attachment",
              let raw = d["attachment"] as? [String: Any],
              let attachment = SessionAttachment.parse(raw) else { return false }
        switch attachment {
        case let .humanPrompt(prompt):
            _ = sink.add(.user, prompt, at: at)
        case let .file(file):
            _ = sink.add(
                .user, "붙임: " + file.name,
                details: .init(attachedFile: file), at: at)
        }
        return true
    }
}
