import SwiftUI
import PreviewEngineKit

/// L0 Host Shell: 파일 드롭, 로딩, 에러 및 빈 화면 상태를 일원화하여 관리하는 최상위 호스트 컨테이너
public struct PreviewHostView<Content: View>: View {
    let isLoading: Bool
    let errorMessage: String?
    let isEmpty: Bool
    let onFileDrop: ((URL) -> Void)?
    let content: () -> Content

    @State private var isTargeted: Bool = false

    public init(
        isLoading: Bool = false,
        errorMessage: String? = nil,
        isEmpty: Bool = false,
        onFileDrop: ((URL) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.isEmpty = isEmpty
        self.onFileDrop = onFileDrop
        self.content = content
    }

    public var body: some View {
        ZStack {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("문서를 파싱하고 렌더링하는 중...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                    Text("문서를 열 수 없습니다")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.viewfinder")
                        .font(.system(size: 56))
                        .foregroundStyle(.tertiary)
                    VStack(spacing: 4) {
                        Text("열린 문서가 없습니다")
                            .font(.title3.weight(.medium))
                        Text("파일(HWPX, XLSX, PDF, PPTX, Mermaid, 이미지, JSON 등)을 여기에 드래그하거나 CLI로 여세요.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content()
            }

            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.1))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(Color.accentColor)
                            Text("문서 추가하기")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    )
            }
        }
        .onDrop(of: ["public.file-url"], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    DispatchQueue.main.async {
                        onFileDrop?(url)
                    }
                }
            }
            return true
        }
    }
}
