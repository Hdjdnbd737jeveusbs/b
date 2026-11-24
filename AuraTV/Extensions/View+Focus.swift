import SwiftUI

// MARK: - tvOS Focus Helpers

extension View {
    /// Applies a scale-up and shadow effect when the view receives focus,
    /// giving it a "lifted card" appearance typical on tvOS.
    func focusableCard() -> some View {
        self.modifier(FocusableCardModifier())
    }

    /// Applies a translucent glass / blur material background.
    func glassMaterial() -> some View {
        self.modifier(GlassMaterialModifier())
    }
}

// MARK: - FocusableCardModifier

private struct FocusableCardModifier: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .shadow(
                color: isFocused ? Color.auraAccent.opacity(0.45) : .clear,
                radius: isFocused ? 20 : 0,
                y: isFocused ? 10 : 0
            )
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - GlassMaterialModifier

private struct GlassMaterialModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
