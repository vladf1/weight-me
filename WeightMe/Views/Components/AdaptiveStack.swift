import SwiftUI

/// Side by side normally; stacked (leading-aligned) at accessibility text sizes, where two columns
/// would wrap a word per line.
struct AdaptiveStack<Content: View>: View {
    var horizontalAlignment: VerticalAlignment = .center
    var spacing: CGFloat? = nil
    @ViewBuilder var content: () -> Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing ?? 6))
            : AnyLayout(HStackLayout(alignment: horizontalAlignment, spacing: spacing))
        layout(content)
    }
}

extension View {
    /// Trailing-aligned beside other content, leading-aligned when stacked at accessibility sizes.
    func adaptiveTrailing(_ size: DynamicTypeSize) -> some View {
        frame(maxWidth: size.isAccessibilitySize ? .infinity : nil,
              alignment: size.isAccessibilitySize ? .leading : .trailing)
    }
}
