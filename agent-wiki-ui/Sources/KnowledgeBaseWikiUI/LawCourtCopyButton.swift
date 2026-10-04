import AppKit
import SwiftUI

/// 심급 건 id 를 클립보드에 복사하는 버튼 — 채팅에서 결정을 요청할 때 붙여 넣는다.
/// UI 모듈에 클립보드 복사의 기존 방식이 없어 이 화면 전용으로 둔다(쓰기 동작이 아니다).
struct LawCourtCopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Label(copied ? L(.LawCourtCopied) : L(.LawCourtCopyID), systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("law-court-copy-id")
    }
}
