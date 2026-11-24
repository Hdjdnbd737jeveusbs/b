import SwiftUI

// MARK: - Subtitle Style Customization Sheet (Wired to "Aa" button)

struct SubtitleStyleSheet: View {
    @Binding var style: SubtitleStyle
    let onDismiss: () -> Void

    @FocusState private var focusedField: StyleField?

    enum StyleField: Hashable {
        case fontPicker
        case sizePicker
        case weightPicker
        case colorPicker
        case opacityPicker
        case offsetPicker
        case done
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    Text("Subtitle Styling")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "textformat.size")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.7))
                }

                // Live Preview
                VStack(spacing: 8) {
                    Text("Live Preview / معاينة مباشرة")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.auraSecondaryText)

                    VStack(spacing: 6) {
                        Text(SubtitleProcessor.process(
                            text: "هذه ترجمة عربية متناسقة مع علامات الترقيم!",
                            isArabic: true
                        ))
                        .font(style.font)
                        .foregroundStyle(style.colorValue)

                        Text("This is a live preview of the styled subtitles.")
                            .font(style.font)
                            .foregroundStyle(style.colorValue)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(style.backgroundOpacity))
                    )
                    .frame(maxWidth: .infinity)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                )

                // Controls
                VStack(spacing: 16) {
                    // Font Family
                    HStack {
                        Text("Font Family")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                        Spacer()
                        Picker("Font", selection: $style.fontName) {
                            ForEach(SubtitleProcessor.availableFonts, id: \.self) { fontName in
                                Text(fontName).tag(fontName)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 260)
                    }

                    Divider().background(Color.white.opacity(0.1))

                    // Font Size
                    HStack {
                        Text("Font Size")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                        Spacer()
                        Picker("Size", selection: $style.fontSize) {
                            Text("Small (34pt)").tag(34.0)
                            Text("Medium (44pt)").tag(44.0)
                            Text("Large (54pt)").tag(54.0)
                            Text("Extra (64pt)").tag(64.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 440)
                    }

                    Divider().background(Color.white.opacity(0.1))

                    // Text Color
                    HStack {
                        Text("Text Color")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                        Spacer()
                        Picker("Color", selection: $style.textColor) {
                            Text("White").tag("White")
                            Text("Yellow").tag("Yellow")
                            Text("Green").tag("Green")
                            Text("Cyan").tag("Cyan")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 380)
                    }

                    Divider().background(Color.white.opacity(0.1))

                    // Background Opacity
                    HStack {
                        Text("Background Opacity")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                        Spacer()
                        Picker("Opacity", selection: $style.backgroundOpacity) {
                            Text("0%").tag(0.0)
                            Text("25%").tag(0.25)
                            Text("50%").tag(0.50)
                            Text("75%").tag(0.75)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 380)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.07))
                )

                Spacer().frame(height: 10)

                // Done Button
                Button(action: onDismiss) {
                    Text("Done")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .focused($focusedField, equals: .done)
            }
            .padding(40)
            .frame(width: 760)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(white: 0.12))
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.6), radius: 24, x: 0, y: 10)
        }
    }
}
