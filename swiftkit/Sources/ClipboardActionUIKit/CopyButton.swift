import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// 텍스트 클립보드 복사 및 완료 피드백(체크마크) 인터랙션을 캡슐화한 표준 UI 컴포넌트.
///
/// 134개 파일에서 반복되던 `NSPasteboard.general` I/O 및 상태 토글 타이머를 대체한다.
public struct CopyButton: View {
    private let text: String
    private let label: String?
    private let iconOnly: Bool
    private let successDuration: TimeInterval

    @State private var copied: Bool = false

    public init(
        text: String,
        label: String? = nil,
        iconOnly: Bool = false,
        successDuration: TimeInterval = 1.5
    ) {
        self.text = text
        self.label = label
        self.iconOnly = iconOnly
        self.successDuration = successDuration
    }

    public var body: some View {
        Button(action: copyToClipboard) {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))

                if !iconOnly, let label = label {
                    Text(copied ? "복사됨" : label)
                        .font(.caption)
                }
            }
        }
        .buttonStyle(.borderless)
        .help(copied ? "복사 완료" : "클립보드에 복사")
    }

    private func copyToClipboard() {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif

        withAnimation(.spring(duration: 0.2)) {
            copied = true
        }

        Task {
            try? await Task.sleep(nanoseconds: UInt64(successDuration * 1_000_000_000))
            withAnimation(.easeInOut(duration: 0.2)) {
                copied = false
            }
        }
    }
}
