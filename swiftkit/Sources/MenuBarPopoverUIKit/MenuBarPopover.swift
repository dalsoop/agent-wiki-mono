import SwiftUI

public struct MenuBarPopoverContent<Content: View>: View {
    public let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(minWidth: 200, minHeight: 150)
            .padding()
    }
}
