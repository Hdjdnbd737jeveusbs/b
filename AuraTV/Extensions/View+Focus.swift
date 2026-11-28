import SwiftUI
import Observation

// MARK: - Smart Navigation, Focus & Scroll Memory (Zero Re-render During Scrolling)

struct AuraContextNavigationTarget: Identifiable, Hashable {
    let id = UUID()
    let tmdbId: Int
    let mediaType: String // "movie" or "series"
    let autoPlay: Bool
}

@Observable
@MainActor
final class AuraNavigationMemory {
    static let shared = AuraNavigationMemory()

    /// Incremented ONLY when a tab should restore focus/scroll (e.g., closing sidebar or returning from detail).
    var restoreTickByTab: [String: Int] = [:]

    /// Incremented ONLY when Home should smoothly scroll back to top on Menu/Back press.
    var homeScrollToTopTick: Int = 0

    /// Root-level destination pushed from Hold-OK quick action menus anywhere in the app.
    var pendingContextNavigation: AuraContextNavigationTarget?

    /// Incremented when returning inside a detail view or switching back cleanly.
    @ObservationIgnored private var lastFocusedItemByTab: [String: String] = [:]
    @ObservationIgnored private var lastScrollItemByTab: [String: String] = [:]
    @ObservationIgnored private var isHomeScrolledPastHero: Bool = false
    @ObservationIgnored private var detailDismissStack: [(id: UUID, dismiss: () -> Void)] = []

    private init() {}

    func restoreTick(for tabKey: String) -> Int {
        restoreTickByTab[tabKey] ?? 0
    }

    /// Writes focused item IDs into non-reactive storage so leaf card focus moves NEVER re-evaluate parent grids.
    func recordFocus(tab tabKey: String, itemId: String, scrollId: String? = nil) {
        lastFocusedItemByTab[tabKey] = itemId
        if let scrollId {
            lastScrollItemByTab[tabKey] = scrollId
        } else {
            lastScrollItemByTab[tabKey] = itemId
        }
    }

    func lastFocusedId(for tabKey: String) -> String? {
        lastFocusedItemByTab[tabKey]
    }

    func lastScrollId(for tabKey: String) -> String? {
        lastScrollItemByTab[tabKey] ?? lastFocusedItemByTab[tabKey]
    }

    func requestRestoreFocus(for tabKey: String) {
        restoreTickByTab[tabKey, default: 0] += 1
    }

    func setHomeScrolledPastHero(_ scrolled: Bool) {
        isHomeScrolledPastHero = scrolled
    }

    func homeScrolledPastHero() -> Bool {
        isHomeScrolledPastHero
    }

    func requestHomeScrollToTop() {
        homeScrollToTopTick += 1
    }

    func pushDetail(id: UUID, dismiss: @escaping () -> Void) {
        detailDismissStack.removeAll { $0.id == id }
        detailDismissStack.append((id: id, dismiss: dismiss))
    }

    func popDetail(id: UUID) {
        detailDismissStack.removeAll { $0.id == id }
    }

    var hasActiveDetail: Bool {
        !detailDismissStack.isEmpty
    }

    @discardableResult
    func dismissTopDetail() -> Bool {
        guard let top = detailDismissStack.last else { return false }
        top.dismiss()
        return true
    }
}

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
    /// Applies a crisp white tvOS focus border and responsive GPU spring scale lift.
    func focusableCard(cornerRadius: CGFloat = 14) -> some View {
        self.modifier(FocusableCardModifier(cornerRadius: cornerRadius))
    }

    /// Applies a dark high-performance card surface with hairline border.
    func glassMaterial(cornerRadius: CGFloat = 16) -> some View {
        self.modifier(GlassMaterialModifier(cornerRadius: cornerRadius))
    }

    /// Triggers opening the left navigation sidebar when pressing Left on leftmost elements.
    func auraLeftEdgeSidebarTrigger(_ enabled: Bool = true) -> some View {
        self.modifier(AuraLeftEdgeSidebarModifier(enabled: enabled))
    }
}

// MARK: - Sidebar Open & Detail Pop Environment Keys

private struct AuraOpenSidebarKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct AuraIsInsideDetailKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var auraOpenSidebar: (() -> Void)? {
        get { self[AuraOpenSidebarKey.self] }
        set { self[AuraOpenSidebarKey.self] = newValue }
    }

    var auraIsInsideDetail: Bool {
        get { self[AuraIsInsideDetailKey.self] }
        set { self[AuraIsInsideDetailKey.self] = newValue }
    }
}

private struct AuraLeftEdgeSidebarModifier: ViewModifier {
    let enabled: Bool
    @Environment(\.auraOpenSidebar) private var openSidebar

    func body(content: Content) -> some View {
        if enabled {
            content.onMoveCommand { direction in
                if direction == .left {
                    openSidebar?()
                }
            }
        } else {
            content
        }
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
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.14), lineWidth: isFocused ? 3.5 : 1)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isFocused)
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
