import SwiftUI

// MARK: - Movies View (Ambient Backdrop + Category Grid)

struct MoviesView: View {
    @State private var viewModel = MoviesViewModel()
    @State private var focusedMovie: TMDBMovie?
    @FocusState private var focusedCategory: MovieCategory?
    @FocusState private var focusedMovieId: Int?

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 230), spacing: 28)
    ]

    var body: some View {
        ZStack {
            // Ambient Backdrop of focused movie
            ambientBackdropView

            // Content
            VStack(alignment: .leading, spacing: 24) {
                // Category Selector Bar
                categoryBar
                    .padding(.horizontal, 50)
                    .padding(.top, 24)

                // Movie Grid
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 32) {
                        ForEach(viewModel.movies(for: viewModel.selectedCategory)) { movie in
                            PosterCardView(movie: movie)
                                .focused($focusedMovieId, equals: movie.id)
                        }
                    }
                    .padding(.horizontal, 50)
                    .padding(.bottom, 60)
                }
            }
        }
        .onChange(of: focusedMovieId) { _, newId in
            guard let newId else { return }
            focusedMovie = viewModel.movies(for: viewModel.selectedCategory).first { $0.id == newId }
        }
        .task {
            await viewModel.loadMovies()
        }
    }

    // MARK: - Ambient Backdrop

    @ViewBuilder
    private var ambientBackdropView: some View {
        ZStack {
            Color.auraBackground.ignoresSafeArea()

            if let path = focusedMovie?.backdropPath ?? viewModel.popularMovies.first?.backdropPath,
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
            ForEach(MovieCategory.allCases) { category in
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
