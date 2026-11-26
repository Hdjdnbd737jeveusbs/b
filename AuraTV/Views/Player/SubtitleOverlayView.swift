import SwiftUI
import CoreGraphics

// MARK: - Subtitle Overlay View (Positioned Cleanly Above Scrubber Bar)

struct SubtitleOverlayView: View {
    let currentCue: AuraSubtitleCue?
    var bitmapCue: CGImage? = nil
    let style: SubtitleStyle
    let fixRTL: Bool
    let fixReversedPunctuation: Bool
    var isHUDVisible: Bool = false
    var suppressPlainText: Bool = false

    var body: some View {
        VStack {
            Spacer()

            if !suppressPlainText, let cue = currentCue {
                let displayedText = SubtitleProcessor.process(
                    text: cue.text,
                    isArabic: cue.isArabic,
                    fixRTL: fixRTL,
                    fixReversedPunctuation: fixReversedPunctuation
                )

                Text(displayedText)
                    .font(style.font)
                    .foregroundStyle(style.colorValue)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, style.backgroundOpacity > 0.01 ? 24 : 8)
                    .padding(.vertical, style.backgroundOpacity > 0.01 ? 10 : 4)
                    .background {
                        if style.backgroundOpacity > 0.01 {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(style.backgroundOpacity))
                        }
                    }
                    .shadow(color: .black.opacity(0.95), radius: 5, x: 0, y: 2)
                    .shadow(color: .black.opacity(0.75), radius: 12, x: 0, y: 0)
                    .padding(.horizontal, 80)
                    // Keep subtitles clearly above the scrubber bar whenever HUD is visible
                    .padding(.bottom, isHUDVisible ? max(CGFloat(style.bottomOffset), 132) : CGFloat(style.bottomOffset))
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            } else if !suppressPlainText, let cgImage = bitmapCue {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 1400, maxHeight: 260)
                    .padding(.horizontal, 80)
                    .padding(.bottom, isHUDVisible ? max(CGFloat(style.bottomOffset), 132) : CGFloat(style.bottomOffset))
                    .transition(.opacity.animation(.easeInOut(duration: 0.12)))
            }
        }
        .ignoresSafeArea()
    }
}
