import Foundation
import MoneyLedgerKit
import SwiftUI

/// 사업체 선택 — 거래 편집기와 거래 목록 필터가 같이 쓴다. 선택값은 BusinessProfile.id(nil = 없음/전체).
/// 사업체가 하나도 없으면 호출부가 숨긴다 — 빈 피커를 보이지 않는다.
struct BusinessPicker: View {
    let label: String
    /// nil 자리의 표기 — 편집기는 "(없음)", 필터는 "(전체)".
    let noneLabel: String
    let businesses: [BusinessProfile]
    @Binding var selection: String?

    var body: some View {
        Picker(label, selection: $selection) {
            Text(noneLabel).tag(String?.none)
            ForEach(businesses) { business in
                Text(business.name).tag(String?.some(business.id))
            }
        }
    }
}

extension LedgerSnapshot {
    /// 거래 표시용 사업체 이름. 보관된 사업체는 목록에 없으므로 id 앞 8자로 대신 보인다.
    func businessName(for businessID: String?) -> String {
        guard let businessID else { return "" }
        return businesses.first { $0.id == businessID }?.name ?? String(businessID.prefix(8))
    }
}
