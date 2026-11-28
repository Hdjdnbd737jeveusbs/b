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
    var fontSize: CGFloat = 16

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: style == .filled ? .heavy : .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(backgroundView)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
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

// MARK: - Dolby Vision Badge View (~25% Larger Reference Scale)

struct DolbyVisionBadgeView: View {
    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 2) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 4.5,
                    topTrailingRadius: 4.5
                )
                .fill(Color.white.opacity(0.92))
                .frame(width: 7.5, height: 15)

                UnevenRoundedRectangle(
                    topLeadingRadius: 4.5,
                    bottomLeadingRadius: 4.5,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0
                )
                .fill(Color.white.opacity(0.92))
                .frame(width: 7.5, height: 15)
            }

            VStack(alignment: .leading, spacing: -1) {
                Text("Dolby")
                    .font(.system(size: 13.5, weight: .bold))
                Text("VISION")
                    .font(.system(size: 7.5, weight: .bold))
                    .tracking(0.8)
            }
            .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 5)
    }
}

// MARK: - Isolated Detail Action Buttons (72pt Scale + Locked 60fps Leaf @FocusState)

struct DetailPlayPillButton: View {
    let title: String
    var progress: Double? = nil
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.system(size: 24, weight: .bold))

                if let progress, progress > 0 && progress < 0.90 {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.22))
                            .frame(width: 48, height: 5)
                        Capsule()
                            .fill(Color.black.opacity(0.88))
                            .frame(width: max(8, 48 * min(max(progress, 0), 1)), height: 5)
                    }
                }

                Text(title)
                    .font(.system(size: 26, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 38)
            .frame(height: 72)
            .background(Color.white)
            .foregroundStyle(.black)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isFocused ? Color.white : .clear, lineWidth: 3.5)
                    .padding(-4)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
    }
}

struct DetailSecondaryPillButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 22, weight: .semibold))
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
            }
            .padding(.horizontal, 28)
            .frame(height: 72)
            .background(isFocused ? Color.white : Color.auraCardSurface)
            .foregroundStyle(isFocused ? .black : .white)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(isFocused ? 1.0 : 0.14), lineWidth: isFocused ? 2 : 1)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
    }
}

struct DetailCircleGlassButton: View {
    let systemName: String
    var isActive: Bool = false
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 72, height: 72)
                .background(isFocused ? Color.white : (isActive ? Color.white.opacity(0.24) : Color.auraCardSurface))
                .foregroundStyle(isFocused ? Color.black : Color.white)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isFocused ? 1.0 : 0.14), lineWidth: isFocused ? 2 : 1)
                )
                .scaleEffect(isFocused ? 1.06 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
    }
}
