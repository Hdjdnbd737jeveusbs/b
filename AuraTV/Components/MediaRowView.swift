import SwiftUI

// MARK: - Media Row View (Reusable Horizontal Shelf with Item Count)

struct MediaRowView<Content: View>: View {
    let title: String
    var count: Int? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section Title + Muted Count (e.g. "Series 19")
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)

                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.42))
                }
            }
            .padding(.horizontal, 156)

            // Horizontal Scrollable Cards
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 28) {
                    content()
                }
                .padding(.horizontal, 156)
                .padding(.vertical, 20)
            }
        }
    }
}
