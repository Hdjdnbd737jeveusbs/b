import SwiftUI

// MARK: - Subtitle Overlay View

struct SubtitleOverlayView: View {
    let currentCue: SubtitleCue?
    let style: SubtitleStyle
    let fixRTL: Bool
    let fixReversedPunctuation: Bool

    var body: some View {
        VStack {
            Spacer()

            if let cue = currentCue {
                let displayedText = SubtitleProcessor.process(
                    text: cue.text,
                    isArabic: cue.isArabic,
                    fixRTL: fixRTL,
                    fixReversedPunctuation: fixReversedPunctuation
                )

                Text(displayedText)
                    .font(style.font)
                    .foregroundStyle(style.colorValue)
                    .multilineTextAlignment(cue.isArabic ? .center : .center)
                    .lineSpacing(6)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(style.backgroundOpacity))
                    )
                    .shadow(color: .black.opacity(0.9), radius: 4, x: 0, y: 2)
                    .padding(.horizontal, 80)
                    .padding(.bottom, CGFloat(style.bottomOffset))
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .ignoresSafeArea()
    }
}
