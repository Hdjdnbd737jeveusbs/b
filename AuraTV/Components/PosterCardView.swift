import SwiftUI
import SwiftData

// MARK: - Poster Card View (Clean 2:3 Portrait Card + Long-Press Context Menu)

struct PosterCardView: View {
    let movie: TMDBMovie
    var overridePosterPath: String? = nil
    var isWatched: Bool = false
    var showWatchedBadge: Bool = true
    var autoPlayTrailersOnFocus: Bool = false

    @FocusState private var isFocused: Bool
    @State private var themeCoordinator = AppThemeCoordinator.shared

    private var isTrailerExpanded: Bool {
        autoPlayTrailersOnFocus && themeCoordinator.expandedHomeCardKey == "movie_\(movie.id)"
    }

    var body: some View {
        NavigationLink(destination: MovieDetailView(tmdbId: movie.id)) {
            ZStack(alignment: .topTrailing) {
                if let path = overridePosterPath ?? movie.posterPath,
                   let url = TMDBService.shared.imageURL(path: path, size: "w500") {
                    AuraCachedImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(2 / 3, contentMode: .fill)
                            .frame(width: 215, height: 322)
                            .clipped()
                    } placeholder: {
                        posterPlaceholder
                    }
                } else {
                    posterPlaceholder
                }

                if isTrailerExpanded {
                    VStack {
                        HStack {
                            Label("Trailer", systemImage: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.75), in: Capsule())
                                .padding(10)
                            Spacer()
                        }
                        Spacer()
                    }
                    .transition(.opacity)
                }

                // Watched indicator badge (top-right circle checkmark)
                if isWatched && showWatchedBadge {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.black.opacity(0.65), in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.45), lineWidth: 1)
                        )
                        .padding(10)
                }
            }
            .frame(width: 215, height: 322)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 3 : 1)
            )
            .scaleEffect(isTrailerExpanded ? 1.11 : (isFocused ? 1.07 : 1.0))
            .shadow(
                color: isFocused ? Color.white.opacity(isTrailerExpanded ? 0.28 : 0.18) : Color.black.opacity(0.45),
                radius: isFocused ? (isTrailerExpanded ? 24 : 18) : 6,
                y: isFocused ? 8 : 3
            )
            .animation(.easeOut(duration: 0.22), value: isFocused)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isTrailerExpanded)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused {
                themeCoordinator.onHomeCardFocused(
                    mediaType: "movie",
                    tmdbId: movie.id,
                    title: movie.title,
                    overview: movie.overview,
                    posterPath: overridePosterPath ?? movie.posterPath,
                    backdropPath: movie.backdropPath,
                    releaseYear: movie.releaseDate.map { String($0.prefix(4)) },
                    voteAverage: movie.voteAverage,
                    autoPlayTrailers: autoPlayTrailersOnFocus
                )
            } else if autoPlayTrailersOnFocus {
                themeCoordinator.onHomeCardBlurred(mediaType: "movie", tmdbId: movie.id)
            }
        }
        .modifier(MediaPosterContextMenuModifier(
            tmdbId: movie.id,
            mediaType: "movie",
            title: movie.title,
            posterPath: overridePosterPath ?? movie.posterPath,
            backdropPath: movie.backdropPath,
            initialWatched: isWatched
        ))
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.auraSurface)
            .frame(width: 215, height: 322)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "film")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.25))
                    Text(movie.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }
    }
}

// MARK: - Shared Poster Long-Press Context Menu Modifier

struct MediaPosterContextMenuModifier: ViewModifier {
    let tmdbId: Int
    let mediaType: String // "movie" or "series"
    let title: String
    let posterPath: String?
    let backdropPath: String?
    var initialWatched: Bool = false

    @Environment(\.modelContext) private var modelContext
    @State private var showChangeArtwork = false
    @State private var isWatchedLocal: Bool?
    @State private var isFavoriteLocal: Bool?

    private var isWatched: Bool {
        isWatchedLocal ?? initialWatched
    }

    private var isFavorite: Bool {
        isFavoriteLocal ?? false
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    toggleWatched()
                } label: {
                    Label(
                        isWatched ? "Mark as Unwatched" : "Mark as Watched",
                        systemImage: "checkmark.circle"
                    )
                }

                Button {
                    toggleFavorite()
                } label: {
                    Label(
                        isFavorite ? "Remove from Favorites" : "Add to Favorites",
                        systemImage: "star"
                    )
                }

                Menu {
                    Button {
                        toggleFavorite()
                    } label: {
                        Label("Watchlist", systemImage: "bookmark")
                    }
                } label: {
                    Label("Add to Collection", systemImage: "square.3.layers.3d")
                }

                Button {
                    showChangeArtwork = true
                } label: {
                    Label("Change Artwork", systemImage: "photo.on.rectangle")
                }

                Button {
                    Task { await applyArtworkSet() }
                } label: {
                    Label("Apply Set", systemImage: "square.3.layers.3d")
                }

                Button {
                    Task { await refreshMetadata() }
                } label: {
                    Label("Refresh Metadata", systemImage: "arrow.clockwise")
                }

                Button {
                    // Trigger intro scan placeholder for series
                } label: {
                    Label("Detect Intros in All Seasons", systemImage: "waveform")
                }

                Button {
                    // Export marks action
                } label: {
                    Label("Export Marks for IntroDB", systemImage: "square.and.arrow.up")
                }
                .disabled(true)
            }
            .sheet(isPresented: $showChangeArtwork) {
                ChangeArtworkView(
                    tmdbId: tmdbId,
                    mediaType: mediaType,
                    title: title,
                    defaultPosterPath: posterPath,
                    defaultBackdropPath: backdropPath,
                    defaultLogoPath: nil
                )
            }
            .onAppear {
                refreshLocalFlags()
            }
    }

    @MainActor
    private func refreshLocalFlags() {
        let id = tmdbId
        let type = mediaType
        let watchDesc = FetchDescriptor<WatchHistory>(
            predicate: #Predicate<WatchHistory> { item in
                item.tmdbId == id && item.mediaType == type
            }
        )
        if let found = try? modelContext.fetch(watchDesc).first {
            isWatchedLocal = found.isCompleted
        }

        let favDesc = FetchDescriptor<WatchlistItem>(
            predicate: #Predicate<WatchlistItem> { item in
                item.tmdbId == id && item.mediaType == type
            }
        )
        if let favs = try? modelContext.fetch(favDesc) {
            isFavoriteLocal = !favs.isEmpty
        }
    }

    @MainActor
    private func toggleWatched() {
        let id = tmdbId
        let type = mediaType
        let descriptor = FetchDescriptor<WatchHistory>(
            predicate: #Predicate<WatchHistory> { item in
                item.tmdbId == id && item.mediaType == type
            }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.isCompleted.toggle()
            existing.lastWatched = Date()
            isWatchedLocal = existing.isCompleted
        } else {
            let entry = WatchHistory(
                tmdbId: tmdbId,
                mediaType: mediaType,
                title: title,
                posterPath: posterPath,
                backdropPath: backdropPath,
                isCompleted: true
            )
            modelContext.insert(entry)
            isWatchedLocal = true
        }
        try? modelContext.save()
    }

    @MainActor
    private func toggleFavorite() {
        let id = tmdbId
        let type = mediaType
        let descriptor = FetchDescriptor<WatchlistItem>(
            predicate: #Predicate<WatchlistItem> { item in
                item.tmdbId == id && item.mediaType == type
            }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            isFavoriteLocal = false
        } else {
            let item = WatchlistItem(
                tmdbId: tmdbId,
                mediaType: mediaType,
                title: title,
                posterPath: posterPath,
                backdropPath: backdropPath,
                addedDate: Date()
            )
            modelContext.insert(item)
            isFavoriteLocal = true
        }
        try? modelContext.save()
    }

    @MainActor
    private func applyArtworkSet() async {
        guard let response = try? await TMDBService.shared.fetchAllArtwork(mediaType: mediaType, id: tmdbId) else {
            return
        }
        let key = CustomArtwork.makeKey(tmdbId: tmdbId, mediaType: mediaType)
        let descriptor = FetchDescriptor<CustomArtwork>(
            predicate: #Predicate<CustomArtwork> { item in
                item.key == key
            }
        )
        let record: CustomArtwork
        if let existing = try? modelContext.fetch(descriptor).first {
            record = existing
        } else {
            record = CustomArtwork(key: key, tmdbId: tmdbId, mediaType: mediaType)
            modelContext.insert(record)
        }
        if let topPoster = response.posters?.first?.filePath {
            record.customPosterPath = topPoster
        }
        if let topBackdrop = response.backdrops?.first?.filePath {
            record.customBackdropPath = topBackdrop
        }
        record.customLogoPath = await TMDBService.shared.fetchBestLogoPath(mediaType: mediaType, id: tmdbId)
        record.updatedAt = Date()
        try? modelContext.save()
    }

    @MainActor
    private func refreshMetadata() async {
        if mediaType == "series" {
            _ = try? await TMDBService.shared.fetchSeriesDetails(id: tmdbId)
        } else {
            _ = try? await TMDBService.shared.fetchMovieDetails(id: tmdbId)
        }
        _ = await TMDBService.shared.fetchBestLogoPath(mediaType: mediaType, id: tmdbId)
    }
}
