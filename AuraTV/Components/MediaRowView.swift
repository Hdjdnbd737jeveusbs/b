import SwiftUI

// MARK: - Media Row View (Reusable Horizontal Shelf)

struct MediaRowView<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Row Title
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 50)

            // Horizontal Scrollable Cards
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 24) {
                    content()
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 16)
            }
        }
    }
}
