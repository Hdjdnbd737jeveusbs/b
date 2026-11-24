import SwiftUI
import SwiftData

// MARK: - Movie Detail View

struct MovieDetailView: View {
    let tmdbId: Int

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = DetailViewModel()
    @FocusState private var focusedButton: DetailButton?

    // Phase 2 & 3: Streaming & Subtitles state
    @State private var showStreamPicker = false
    @State private var showPlayer = false
    @State private var selectedStreamURL: URL?
    @State private var availableStreams: [StremioStream] = []
    @State private var isLoadingStreams = false
    @State private var streamError: String?
    @State private var playerViewModel = PlayerViewModel()
    @State private var movieImdbId: String?

    enum DetailButton: Hashable {
        case play
        case rewatch
        case watchlist
        case artwork
        case more
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Color.black.ignoresSafeArea()

                // Right-side backdrop image
                backdropImage(geometry: geometry)

                // Left-side gradient fade
                leftGradientOverlay(geometry: geometry)

                // Left-side content
                contentOverlay(geometry: geometry)
            }
        }
        .ignoresSafeArea()
        .task {
            await viewModel.loadMovieDetail(id: tmdbId, context: modelContext)
        }
        .sheet(isPresented: $showStreamPicker) {
            StreamPickerSheet(
                title: viewModel.movieDetail?.title ?? "Movie",
                streams: availableStreams,
                onSelect: { stream in
                    if let urlString = stream.url, let url = URL(string: urlString) {
                        startPlayback(url: url, resumeFrom: viewModel.watchProgress?.currentTime ?? 0)
                    }
                },
                onDismiss: { showStreamPicker = false }
            )
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView(viewModel: playerViewModel)
        }
        .overlay {
            if isLoadingStreams {
                ZStack {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Finding streams...")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .alert("Stream Error", isPresented: .init(
            get: { streamError != nil },
            set: { if !$0 { streamError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(streamError ?? "Unknown error")
        }
    }

    // MARK: - Backdrop Image (Right 65% width)

    @ViewBuilder
    private func backdropImage(geometry: GeometryProxy) -> some View {
        let imageWidth = geometry.size.width * 0.65
        let imageHeight = geometry.size.height

        HStack {
            Spacer()
            if let path = viewModel.movieDetail?.backdropPath ?? viewModel.movieDetail?.posterPath,
               let url = TMDBService.shared.imageURL(path: path, size: "original") {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: imageWidth, height: imageHeight)
                            .clipped()
                    case .failure, .empty:
                        backdropPlaceholder(width: imageWidth, height: imageHeight)
                    @unknown default:
                        backdropPlaceholder(width: imageWidth, height: imageHeight)
                    }
                }
            } else {
                backdropPlaceholder(width: imageWidth, height: imageHeight)
            }
        }
    }

    @ViewBuilder
    private func backdropPlaceholder(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color(white: 0.08))
            .frame(width: width, height: height)
            .overlay {
                Image(systemName: "film")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.15))
            }
    }

    // MARK: - Left Gradient Overlay

    @ViewBuilder
    private func leftGradientOverlay(geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            Color.black
                .frame(width: geometry.size.width * 0.38)

            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black.opacity(0.92), location: 0.25),
                    .init(color: .black.opacity(0.70), location: 0.55),
                    .init(color: .black.opacity(0.30), location: 0.80),
                    .init(color: .clear, location: 1.0)
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geometry.size.width * 0.35)

            Spacer()
        }
        .ignoresSafeArea()
    }

    // MARK: - Content Overlay

    @ViewBuilder
    private func contentOverlay(geometry: GeometryProxy) -> some View {
        let contentWidth = geometry.size.width * 0.52

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                Spacer()
                    .frame(height: geometry.size.height * 0.14)

                // Title
                titleSection

                // Metadata line (Year · PG-13 · 2h 23m · Action, Adventure)
                metadataLine

                // Quality badges (4K, Dolby Vision, 5.1, CC, SDH, AR)
                qualityBadges

                // Rating
                ratingView

                // Overview
                overviewSection

                // Action buttons row (Play/Resume, Rewatch, Watchlist, More)
                actionButtons

                // Cast section
                castSection

                Spacer()
                    .frame(height: 60)
            }
            .padding(.leading, 70)
            .frame(width: contentWidth, alignment: .leading)
        }
    }

    // MARK: - Title

    @ViewBuilder
    private var titleSection: some View {
        if let detail = viewModel.movieDetail {
            Text(detail.title.uppercased())
                .font(.system(size: 64, weight: .bold))
                .tracking(6)
                .foregroundStyle(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.8), radius: 10, x: 0, y: 4)
        } else {
            ProgressView()
                .tint(.white)
        }
    }

    // MARK: - Metadata Line

    @ViewBuilder
    private var metadataLine: some View {
        if let detail = viewModel.movieDetail {
            HStack(spacing: 10) {
                if let date = detail.releaseDate, date.count >= 4 {
                    Text(String(date.prefix(4)))
                }

                if let cert = viewModel.certification, !cert.isEmpty {
                    Text("·")
                    BadgeView(text: cert, style: .outlined, fontSize: 13)
                }

                if let runtime = detail.runtime, runtime > 0 {
                    Text("·")
                    Text(formatRuntime(runtime))
                }

                if let genres = detail.genres, !genres.isEmpty {
                    Text("·")
                    Text(genres.map(\.name).joined(separator: ", "))
                        .lineLimit(1)
                }
            }
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - Quality Badges

    @ViewBuilder
    private var qualityBadges: some View {
        HStack(spacing: 8) {
            BadgeView(text: "4K", style: .filled)
            BadgeView(text: "Dolby Vision", style: .outlined)
            BadgeView(text: "5.1", style: .outlined)
            BadgeView(text: "CC", style: .outlined)
            BadgeView(text: "SDH", style: .outlined)
            BadgeView(text: "AR", style: .outlined)
        }
    }

    // MARK: - Rating

    @ViewBuilder
    private var ratingView: some View {
        if let detail = viewModel.movieDetail, let vote = detail.voteAverage, vote > 0 {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 20))
                Text(String(format: "%.1f", vote))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Overview

    @ViewBuilder
    private var overviewSection: some View {
        if let overview = viewModel.movieDetail?.overview, !overview.isEmpty {
            Text(overview)
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(4)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 20) {
            // Play / Resume Button
            Button(action: { playMovie() }) {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22))

                    if let progress = viewModel.watchProgress, progress.progress > 0 && !progress.isCompleted {
                        // Resume layout with progress bar & remaining time
                        HStack(spacing: 12) {
                            // Progress bar
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.black.opacity(0.25))
                                    .frame(width: 80, height: 5)
                                Capsule()
                                    .fill(Color.black)
                                    .frame(width: 80 * progress.progress, height: 5)
                            }

                            if !progress.remainingTimeFormatted.isEmpty {
                                Text(progress.remainingTimeFormatted)
                                    .font(.system(size: 18, weight: .semibold))
                            }
                        }
                    } else {
                        Text("Play")
                            .font(.system(size: 22, weight: .bold))
                    }
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 16)
                .background(Color.white)
                .foregroundStyle(.black)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .focused($focusedButton, equals: .play)
            .scaleEffect(focusedButton == .play ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: focusedButton)

            // Rewatch Button
            Button(action: { rewatchMovie() }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 18))
                    Text("Rewatch")
                        .font(.system(size: 20, weight: .medium))
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.12))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .focused($focusedButton, equals: .rewatch)
            .scaleEffect(focusedButton == .rewatch ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: focusedButton)

            // Watchlist Toggle
            Button(action: {
                viewModel.toggleWatchlist(
                    tmdbId: tmdbId,
                    mediaType: "movie",
                    title: viewModel.movieDetail?.title ?? "",
                    posterPath: viewModel.movieDetail?.posterPath,
                    backdropPath: viewModel.movieDetail?.backdropPath,
                    context: modelContext
                )
            }) {
                Image(systemName: viewModel.isInWatchlist ? "checkmark" : "plus")
                    .font(.system(size: 22, weight: .bold))
                    .padding(16)
                    .background(Color.white.opacity(0.12))
                    .foregroundStyle(viewModel.isInWatchlist ? Color.green : Color.white)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .focused($focusedButton, equals: .watchlist)
            .scaleEffect(focusedButton == .watchlist ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: focusedButton)

            // Artwork Picker Button (Matches Screenshot 2)
            Button(action: { /* Change Artwork */ }) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(16)
                    .background(Color.white.opacity(0.12))
                    .foregroundStyle(.white)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .focused($focusedButton, equals: .artwork)
            .scaleEffect(focusedButton == .artwork ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: focusedButton)

            // More Options Button
            Button(action: { /* Phase 4: Change Artwork */ }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .bold))
                    .padding(16)
                    .background(Color.white.opacity(0.12))
                    .foregroundStyle(.white)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .focused($focusedButton, equals: .more)
            .scaleEffect(focusedButton == .more ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: focusedButton)
        }
        .padding(.top, 6)
    }

    // MARK: - Cast Section

    @ViewBuilder
    private var castSection: some View {
        if !viewModel.cast.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Cast")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(viewModel.cast.prefix(15)) { member in
                            CastCardView(member: member)
                        }
                    }
                }
            }
            .padding(.top, 14)
        }
    }

    // MARK: - Helpers

    private func formatRuntime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }

    // MARK: - Phase 2: Playback Actions

    private func playMovie() {
        Task {
            isLoadingStreams = true
            streamError = nil
            do {
                if movieImdbId == nil {
                    let ext = try? await TMDBService.shared.fetchMovieExternalIds(id: tmdbId)
                    movieImdbId = ext?.imdbId
                }
                let streams = try await AIOStreamsService.shared.fetchStreamsForMovie(tmdbId: tmdbId)
                availableStreams = streams
                isLoadingStreams = false

                if streams.count == 1, let url = URL(string: streams[0].url ?? "") {
                    // Single stream — play directly
                    startPlayback(url: url, resumeFrom: viewModel.watchProgress?.currentTime ?? 0)
                } else {
                    showStreamPicker = true
                }
            } catch {
                isLoadingStreams = false
                streamError = error.localizedDescription
            }
        }
    }

    private func rewatchMovie() {
        // Reset progress and play from beginning
        if let progress = viewModel.watchProgress {
            progress.currentTime = 0
            progress.isCompleted = false
            try? modelContext.save()
        }
        playMovie()
    }

    private func startPlayback(url: URL, resumeFrom: Double = 0) {
        let detail = viewModel.movieDetail
        playerViewModel = PlayerViewModel()
        playerViewModel.configure(
            url: url,
            title: detail?.title ?? "Movie",
            backdropPath: detail?.backdropPath,
            posterPath: detail?.posterPath,
            tmdbId: tmdbId,
            mediaType: "movie",
            resumeFrom: resumeFrom,
            imdbId: movieImdbId ?? ""
        )
        showStreamPicker = false
        showPlayer = true
    }
}
