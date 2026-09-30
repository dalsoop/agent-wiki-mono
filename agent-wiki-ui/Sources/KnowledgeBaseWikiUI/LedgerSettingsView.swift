import KnowledgeBaseWikiCore
import SwiftUI
import SettingsUIKit

/// 설정 — 정본·무결성·복제·보호가 전부 여기 드러난다 (배관 상태의 단일 화면).
struct LedgerSettingsView: View {
    @Bindable var model: LedgerModel

    var body: some View {
        Form {
            Section {
                AboutSection()
            }

            Section("정본") {
                LabeledContent("위치", value: model.rootURL?.path ?? "(미지정)")
                LabeledContent("객체", value: "\(model.objects.count)개 (전부 md, 파생 캐시 없음)")
                Button("폴더 바꾸기…") { model.chooseRoot() }
            }
            Section("무결성 (변조·증발 감지)") {
                LabeledContent("검사 결과",
                    value: model.integrityProblemCount == 0 ? "이상 없음" : "문제 \(model.integrityProblemCount)건")
                    .foregroundStyle(model.integrityProblemCount == 0 ? .primary : Color.red)
                if let checkpoint = model.lastCheckpoint {
                    LabeledContent("마지막 체크포인트",
                        value: "\(checkpoint.published.formatted(.dateTime)) · \(checkpoint.title?.replacingOccurrences(of: "체크포인트: ", with: "") ?? "")")
                } else {
                    LabeledContent("마지막 체크포인트", value: "없음 — 기준점 필요")
                        .foregroundStyle(.orange)
                }
                LabeledContent("자동 체크포인트",
                    value: model.checkpointJobLoaded ? "매일 21:30 (새 발행 있을 때만)" : "미등록")
                    .foregroundStyle(model.checkpointJobLoaded ? .primary : Color.orange)
                Button("지금 검사") { model.refreshProtectionStatus() }
            }
            GujoTransportSection(model: model)
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 440)
        .onAppear { model.refreshProtectionStatus() }
    }
}
