import SwiftUI

// MARK: - Custom Platter-Free tvOS Button Style

/// Opts out of UIKit's default tvOS white focus platter so custom cards,
/// hero banners, and pills render strictly with their own focus borders/scales.
struct AuraButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.88 : 1.0)
    }
}

// MARK: - tvOS Focus Helpers

extension View {
    /// Applies a crisp white tvOS focus border and smooth scale lift.
    func focusableCard(cornerRadius: CGFloat = 14) -> some View {
        self.modifier(FocusableCardModifier(cornerRadius: cornerRadius))
    }

    /// Applies a dark frosted-glass surface with hairline border.
    func glassMaterial(cornerRadius: CGFloat = 16) -> some View {
        self.modifier(GlassMaterialModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - FocusableCardModifier

private struct FocusableCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 3 : 1)
            )
            .scaleEffect(isFocused ? 1.07 : 1.0)
            .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}

// MARK: - GlassMaterialModifier

private struct GlassMaterialModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(Color.auraCardSurface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.auraGlassBorder, lineWidth: 1)
            )
    }
}
