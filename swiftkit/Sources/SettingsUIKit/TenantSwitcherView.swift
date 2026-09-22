import SwiftUI

/// Gujo 계열 앱이 쓰던 테넌트 메뉴 피커.
public struct TenantSwitcherView: View {
    public var label: String
    public var defaultTitle: String
    public var tenants: [String]
    @Binding public var selection: String

    public init(
        label: String,
        defaultTitle: String,
        tenants: [String],
        selection: Binding<String>
    ) {
        self.label = label
        self.defaultTitle = defaultTitle
        self.tenants = tenants
        self._selection = selection
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Picker(label, selection: $selection) {
                Text(defaultTitle).tag("")
                ForEach(tenants, id: \.self) { id in
                    Text(id).tag(id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityLabel(label)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
