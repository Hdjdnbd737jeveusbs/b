import SwiftUI

// MARK: - Series View (16:9 Title Cards Grid)

struct SeriesView: View {
    @State private var viewModel = SeriesViewModel()
    @State private var focusedSeries: TMDBSeries?
    @FocusState private var focusedCategory: SeriesCategory?
    @FocusState private var focusedSeriesId: Int?

    private let columns = [
        GridItem(.adaptive(minimum: 360, maximum: 400), spacing: 28)
    ]

    var body: some View {
        ZStack {
            // Ambient Backdrop
            ambientBackdropView

            // Content
            VStack(alignment: .leading, spacing: 24) {
                // Category Selector Bar
                categoryBar
                    .padding(.horizontal, 50)
                    .padding(.top, 24)

                // Series Grid (16:9 cards)
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 32) {
                        ForEach(viewModel.series(for: viewModel.selectedCategory)) { series in
                            SeriesCardView(series: series)
                                .focused($focusedSeriesId, equals: series.id)
                        }
                    }
                    .padding(.horizontal, 50)
                    .padding(.bottom, 60)
                }
            }
        }
        .onChange(of: focusedSeriesId) { _, newId in
            guard let newId else { return }
            focusedSeries = viewModel.series(for: viewModel.selectedCategory).first { $0.id == newId }
        }
        .task {
            await viewModel.loadSeries()
        }
    }

    // MARK: - Ambient Backdrop

    @ViewBuilder
    private var ambientBackdropView: some View {
        ZStack {
            Color.auraBackground.ignoresSafeArea()

            if let path = focusedSeries?.backdropPath ?? viewModel.popularSeries.first?.backdropPath,
               let url = TMDBService.shared.imageURL(path: path, size: "w1280") {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .ignoresSafeArea()
                            .blur(radius: 40)
                            .opacity(0.35)
                            .overlay(Color.black.opacity(0.55))
                    }
                }
            }
        }
    }

    // MARK: - Category Bar

    @ViewBuilder
    private var categoryBar: some View {
        HStack(spacing: 16) {
            ForEach(SeriesCategory.allCases) { category in
                Button(action: {
                    withAnimation {
                        viewModel.selectedCategory = category
                    }
                }) {
                    Text(category.rawValue)
                        .font(.system(size: 20, weight: viewModel.selectedCategory == category ? .bold : .medium))
                        .foregroundStyle(viewModel.selectedCategory == category ? Color.black : Color.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 12)
                        .background(
                            viewModel.selectedCategory == category
                            ? Color.white
                            : Color.white.opacity(0.12)
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(focusedCategory == category ? Color.auraAccent : Color.clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .focused($focusedCategory, equals: category)
                .scaleEffect(focusedCategory == category ? 1.06 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: focusedCategory)
            }
        }
    }
}
