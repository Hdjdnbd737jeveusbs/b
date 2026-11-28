import SwiftUI

extension Color {
    /// Deep dark cinema background (#090B10).
    static let auraBackground = Color(red: 9 / 255, green: 11 / 255, blue: 16 / 255)

    /// Elevated translucent surface for dark cards, settings tiles, and sheets.
    static let auraSurface = Color(red: 19 / 255, green: 22 / 255, blue: 30 / 255)

    /// High-performance 60fps dark card/modal surface (#16181F at 90% opacity, zero blur overhead).
    static let auraCardSurface = Color(red: 22 / 255, green: 24 / 255, blue: 31 / 255).opacity(0.90)

    /// Subtle frosted glass card fill.
    static let auraGlassFill = Color.white.opacity(0.06)

    /// Subtle hairline border for glass containers.
    static let auraGlassBorder = Color.white.opacity(0.14)

    /// Accent highlight for secondary controls when needed.
    static let auraAccent = Color(red: 0.40, green: 0.44, blue: 0.90)

    /// Primary text color — pure white.
    static let auraText = Color.white

    /// Secondary text color — muted gray for metadata, subtitles, and counts.
    static let auraSecondaryText = Color(white: 0.56)
}
