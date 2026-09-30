import KnowledgeBaseWikiCore
import SwiftUI

/// 4층 구분 배지 — 객체가 사실(fact)인지 해석(interpretation)인지 한눈에.
/// 사실=에이전트무관 기록(run·체크포인트·선별), 해석=경합하는 판단(분류·반박·이의).
/// 둘 다 아니면(개념·엔티티·근거 등 지식) 아무것도 안 그린다.
struct LayerBadge: View {
    let object: LedgerObject

    var body: some View {
        if object.isFact {
            badge("사실", .blue)
        } else if object.isInterpretation {
            badge("해석", .brown)
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}
