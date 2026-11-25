import SwiftUI

// MARK: - Subtitle Appearance & Styling Panel (Zero Segmented Truncation)

struct SubtitleStyleSheet: View {
    @Binding var style: SubtitleStyle
    let onDismiss: () -> Void

    @FocusState private var focusedField: StyleField?

    enum StyleField: Hashable {
        case fontFamily
        case fontSize
        case fontWeight
        case textColor
        case backgroundOpacity
        case verticalPosition
        case done
    }

    private let sizeOptions: [Double] = [34, 44, 54, 64]
    private let weightOptions = ["Regular", "Medium", "Semibold", "Bold"]
    private let colorOptions = ["White", "Yellow", "Green", "Cyan"]
    private let opacityOptions: [Double] = [0.0, 0.25, 0.5, 0.75]
    private let bottomOffsetOptions: [Double] = [40, 60, 100, 140]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Subtitle Appearance")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "textformat.size")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.7))
            }

            // Live Arabic & English Preview
            VStack(spacing: 8) {
                Text("Live Preview / معاينة مباشرة")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.auraSecondaryText)

                VStack(spacing: 6) {
                    Text(SubtitleProcessor.process(
                        text: "هذه ترجمة عربية متناسقة مع علامات الترقيم!",
                        isArabic: true
                    ))
                    .font(style.font)
                    .foregroundStyle(style.colorValue)

                    Text("The dark knight rises in 4K HDR.")
                        .font(style.font)
                        .foregroundStyle(style.colorValue)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.black.opacity(style.backgroundOpacity), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity)
            }
            .padding(16)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))

            // Clean Full-Width Cycle Rows
            VStack(spacing: 10) {
                cycleRow(title: "Font Family", value: style.fontName, field: .fontFamily) {
                    style.fontName = nextValue(after: style.fontName, in: SubtitleProcessor.availableFonts)
                }

                cycleRow(title: "Font Size", value: "\(Int(style.fontSize)) pt", field: .fontSize) {
                    style.fontSize = nextValue(after: style.fontSize, in: sizeOptions)
                }

                cycleRow(title: "Font Weight", value: style.fontWeight, field: .fontWeight) {
                    style.fontWeight = nextValue(after: style.fontWeight, in: weightOptions)
                }

                cycleRow(title: "Text Color", value: style.textColor, field: .textColor) {
                    style.textColor = nextValue(after: style.textColor, in: colorOptions)
                }

                cycleRow(title: "Background Box Opacity", value: "\(Int(style.backgroundOpacity * 100))%", field: .backgroundOpacity) {
                    style.backgroundOpacity = nextValue(after: style.backgroundOpacity, in: opacityOptions)
                }

                cycleRow(title: "Vertical Position", value: "\(Int(style.bottomOffset)) pt bottom", field: .verticalPosition) {
                    style.bottomOffset = nextValue(after: style.bottomOffset, in: bottomOffsetOptions)
                }
            }

            Button(action: onDismiss) {
                Text("Done")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white, in: Capsule())
                    .scaleEffect(focusedField == .done ? 1.03 : 1.0)
                    .animation(.easeOut(duration: 0.16), value: focusedField)
            }
            .buttonStyle(AuraButtonStyle())
            .focusEffectDisabled()
            .focused($focusedField, equals: .done)
        }
        .padding(36)
        .frame(width: 760)
        .background(Color.auraSurface.opacity(0.95), in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.75), radius: 28, y: 12)
        .padding(.trailing, 70)
        .padding(.bottom, 64)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .defaultFocus($focusedField, .fontSize)
    }

    @ViewBuilder
    private func cycleRow(title: String, value: String, field: StyleField, action: @escaping () -> Void) -> some View {
        let isFocused = focusedField == field

        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isFocused ? Color.black : Color.white)
                Spacer()
                HStack(spacing: 8) {
                    Text(value)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isFocused ? Color.black.opacity(0.78) : Color.white.opacity(0.72))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isFocused ? Color.black.opacity(0.6) : Color.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? Color.white : Color.white.opacity(0.06))
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.16), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedField, equals: field)
    }

    private func nextValue<T: Equatable>(after current: T, in list: [T]) -> T {
        guard let idx = list.firstIndex(of: current) else { return list.first ?? current }
        return list[(idx + 1) % list.count]
    }
}
