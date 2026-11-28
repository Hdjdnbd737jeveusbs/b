import SwiftUI

// MARK: - Media Row View (Reusable Horizontal Shelf with Item Count)

struct MediaRowView<Content: View>: View {
    let title: String
    var count: Int? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 80)

            // Horizontal Scrollable Cards (400x225 16:9, spacing 32)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 32) {
                    content()
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 14)
            }
            .focusSection()
        }
    }
}
