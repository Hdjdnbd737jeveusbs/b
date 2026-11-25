import SwiftUI

// MARK: - Badge Style

enum BadgeStyle {
    case outlined
    case filled
    case translucent
    case darkPill
}

// MARK: - Badge View

struct BadgeView: View {
    let text: String
    var style: BadgeStyle = .outlined
    var fontSize: CGFloat = 14

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: style == .filled ? .heavy : .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
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
        case .outlined, .translucent, .darkPill:
            return .white.opacity(0.9)
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .filled:
            Color.white.opacity(0.92)
        case .outlined:
            Color.white.opacity(0.06)
        case .translucent:
            Color.white.opacity(0.18)
        case .darkPill:
            Color.black.opacity(0.8)
        }
    }

    private var borderColor: Color {
        switch style {
        case .outlined:
            return Color.white.opacity(0.45)
        case .filled, .translucent, .darkPill:
            return .clear
        }
    }
}

// MARK: - Dolby Vision Badge View

struct DolbyVisionBadgeView: View {
    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 1.5) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 4,
                    topTrailingRadius: 4
                )
                .fill(Color.white.opacity(0.92))
                .frame(width: 6, height: 12)

                UnevenRoundedRectangle(
                    topLeadingRadius: 4,
                    bottomLeadingRadius: 4,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0
                )
                .fill(Color.white.opacity(0.92))
                .frame(width: 6, height: 12)
            }

            VStack(alignment: .leading, spacing: -1) {
                Text("Dolby")
                    .font(.system(size: 11, weight: .bold))
                Text("VISION")
                    .font(.system(size: 6, weight: .bold))
                    .tracking(0.8)
            }
            .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 4)
    }
}
