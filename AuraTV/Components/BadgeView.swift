import SwiftUI

// MARK: - Badge Style

enum BadgeStyle {
    case outlined
    case filled
    case translucent
}

// MARK: - Badge View

struct BadgeView: View {
    let text: String
    var style: BadgeStyle = .outlined
    var fontSize: CGFloat = 14

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundView)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(borderColor, lineWidth: style == .outlined ? 1 : 0)
            )
    }

    private var foregroundColor: Color {
        switch style {
        case .filled:
            return .black
        case .outlined, .translucent:
            return .white.opacity(0.85)
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .filled:
            Color.white
        case .outlined:
            Color.white.opacity(0.08)
        case .translucent:
            Color.white.opacity(0.18)
        }
    }

    private var borderColor: Color {
        switch style {
        case .outlined:
            return Color.white.opacity(0.4)
        case .filled, .translucent:
            return .clear
        }
    }
}
