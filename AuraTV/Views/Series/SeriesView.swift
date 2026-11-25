import SwiftUI
import SwiftData

// MARK: - Series View (16:9 Title Cards Grid with Safe-Area Clearance)

struct SeriesView: View {
    @Query private var artworkOverrides: [CustomArtwork]
    @State private var viewModel = SeriesViewModel()
    @State private var focusedSeries: TMDBSeries?
    @FocusState private var focusedCategory: SeriesCategory?
    @FocusState private var focusedSeriesId: Int?

    private let columns = [
        GridItem(.adaptive(minimum: 360, maximum: 400), spacing: 28)
    ]

    private var customBackdrops: [Int: String] {
        Dictionary(
            artworkOverrides.filter { $0.mediaType == "series" }.compactMap { item in
                item.customBackdropPath.map { (item.tmdbId, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        ZStack {
            // Ambient Backdrop
            ambientBackdropView

            // Content pushed clearly below the floating tvOS sidebar pill (< Series)
            VStack(alignment: .leading, spacing: 26) {
                categoryBar
                    .padding(.horizontal, 75)
                    .padding(.top, 84)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 32) {
                        ForEach(viewModel.series(for: viewModel.selectedCategory)) { series in
                            SeriesCardView(
                                series: series,
                                overrideBackdropPath: customBackdrops[series.id]
                            )
                            .focused($focusedSeriesId, equals: series.id)
                        }
                    }
                    .padding(.horizontal, 75)
                    .padding(.top, 8)
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

            let targetSeries = focusedSeries ?? viewModel.series(for: viewModel.selectedCategory).first ?? viewModel.popularSeries.first
            if let path = targetSeries.flatMap({ customBackdrops[$0.id] ?? $0.backdropPath ?? $0.posterPath }),
               let url = TMDBService.shared.imageURL(path: path, size: "w1280") {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .ignoresSafeArea()
                            .blur(radius: 40)
                            .opacity(0.32)
                            .overlay(Color.auraBackground.opacity(0.65))
                    }
                }
            }
        }
    }

    // MARK: - Category Bar

    @ViewBuilder
    private var categoryBar: some View {
        HStack(spacing: 22) {
            ForEach(SeriesCategory.allCases) { category in
                let isSelected = viewModel.selectedCategory == category
                let isFocused = focusedCategory == category

                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        viewModel.selectedCategory = category
                    }
                }) {
                    Text(category.rawValue)
                        .font(.system(size: 19, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected || isFocused ? Color.black : Color.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 12)
                        .background(
                            (isSelected || isFocused)
                            ? Color.white
                            : Color.white.opacity(0.1)
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(isFocused ? Color.white : Color.white.opacity(0.14), lineWidth: isFocused ? 2 : 1)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()
                .focused($focusedCategory, equals: category)
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(.easeOut(duration: 0.16), value: focusedCategory)
            }
        }
    }
}
