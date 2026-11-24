# AuraTV — Full Specification

> A native Apple TV 4K (tvOS 18+) SwiftUI streaming application.

---

## Architecture Overview

| Layer | Technology |
|---|---|
| **Platform** | tvOS 18+ (SwiftUI, SwiftData) |
| **UI Framework** | SwiftUI with tvOS focus system |
| **Metadata** | TMDB API v3 |
| **Streaming Source** | AIOStreams (Stremio-compatible manifest) — Phase 2 |
| **Player Engine** | KSPlayer / MPVKit via SPM — Phase 2 |
| **Local Storage** | SwiftData (Watch History, Settings, Collections) |
| **Backup** | JSON export / import |

### Explicit Non-Goals
- NO Plex, NO NAS, NO Trakt integration.

---

## UI Design Reference

### Navigation — Auto-hiding Glass Sidebar
- Glass/blur material sidebar that auto-hides when focus moves to content.
- Items: **Search**, **Home**, **Series**, **Movies**, **Collections**, **Settings**.
- Selected item shows white highlight capsule.
- When collapsed: breadcrumb at top-left shows `‹ 🏠 Home` style indicator.
- Implemented via tvOS `TabView` with `.sidebarAdaptable` tab style.

### Home Screen — Spotlight Carousel
- Full-width hero carousel at top with large backdrop images.
- Overlay text: category label ("RECENTLY ADDED"), title (large bold), metadata badges (certification, year, season count, genres, ★ rating).
- Page indicator dots below the carousel.
- Below: horizontal scrolling rows:
  - **Continue Watching** — 16:9 poster/backdrop cards with title below.
  - **Trending Movies** — poster cards.
  - **Trending Series** — poster cards.
  - **Top Rated** — poster cards.

### Movies Tab
- Ambient full-screen backdrop of focused movie (blurred behind content).
- Grid of movie poster cards (2:3 ratio).
- Categories: Popular, Top Rated, Now Playing, Upcoming.
- Horizontal category rows or switchable grid.

### Series Tab
- Grid of series cards using 16:9 (backdrop) title cards.
- Categories: Popular, Top Rated, Airing Today, On The Air.

### Detail View
- Full-screen backdrop image on the right half.
- Left side content:
  - **Title** (large, letter-spaced for cinematic feel).
  - **Metadata line**: Year · Certification · Runtime · Genres.
  - **Quality badges**: 4K, Dolby Vision, 5.1, CC, SDH, AR (rounded rectangles).
  - **Star rating**: ★ with score.
  - **Overview**: Multi-line description text.
  - **Action buttons row**:
    - Play button with progress bar + remaining time (e.g., "1h 43m").
    - Rewatch button.
    - Watchlist toggle (checkmark).
    - Cast/crew icon.
    - More options (…).
  - **Cast section**: Horizontal scroll of cast member cards.
- For Series: additional Seasons/Episodes picker below.

### Search View
- tvOS search field at top.
- Real-time results grid below (movies + series mixed).

### Collections View
- User-created collections (Watchlist built-in).
- Grid of collection cards, each showing a collage or primary poster.

### Settings View
- TMDB API Key input field.
- AIOStreams Manifest URL (Phase 2).
- Preferred quality, language, subtitle language.
- Watch history export/import (JSON).
- About / version info.

---

## 4-Phase Development Plan

### Phase 1 — Foundation & UI ✦ (Current)

**Scope**: Project structure, all SwiftUI views matching the reference screenshots, TMDB API integration, SwiftData models for watch history and settings.

| Task | Details |
|---|---|
| **Project Setup** | Xcode project structure for tvOS 18+, folder organization (Models, Services, ViewModels, Views, Extensions). |
| **SwiftData Models** | `WatchHistory`, `AppSettings`, `WatchlistItem` — persistent local storage. |
| **TMDB Service** | Full networking layer: trending, popular, top-rated, search, details, credits. Image URL builder. |
| **Navigation** | `ContentView` with `TabView(.sidebarAdaptable)` — glass sidebar with auto-hide. |
| **Home View** | `SpotlightCarouselView` (hero carousel), `ContinueWatchingRow`, trending/popular rows. |
| **Movies View** | Ambient backdrop, movie poster grid with categories. |
| **Series View** | 16:9 backdrop card grid with categories. |
| **Detail Views** | `MovieDetailView`, `SeriesDetailView` — full detail layout matching screenshots. |
| **Search View** | tvOS search with real-time TMDB results. |
| **Collections View** | Watchlist display, future collection support. |
| **Settings View** | API key entry, preferences, JSON export/import. |
| **Components** | `PosterCardView`, `EpisodeCardView`, `BadgeView`, `MediaRowView`, `CastCardView`. |
| **Focus Navigation** | Proper tvOS focus handling across all views. |

### Phase 2 — Streaming & Playback

**Scope**: AIOStreams manifest parsing, KSPlayer/MPVKit integration, 4K HDR10+ playback, loading screen.

| Task | Details |
|---|---|
| **AIOStreams Parser** | Parse Stremio-compatible manifest JSON. Stream selection (quality, provider). |
| **KSPlayer / MPVKit** | SPM integration. Custom player UI overlay. 4K, HDR10, HDR10+, Dolby Vision passthrough. |
| **Player Controls** | Play/pause, seek, chapter markers, audio track selection. |
| **Loading Screen** | AuraTV logo animation on app launch. |
| **Resume Playback** | Auto-resume from SwiftData `WatchHistory.currentTime`. |
| **Stream Quality Badge** | Detect and display actual stream quality (4K, Dolby, etc.) on detail view. |

### Phase 3 — Subtitles

**Scope**: Multi-source subtitle aggregation, custom Arabic font support, advanced subtitle controls.

| Task | Details |
|---|---|
| **Subtitle Aggregator** | Fetch from: Wyzie, SubDL, SubSource, OpenSubtitles. Unified results list. |
| **Language Selection** | Filter by language, prefer user's configured subtitle language. |
| **Custom Arabic Fonts** | Load remote `.ttf`/`.otf` fonts for Arabic subtitle rendering. |
| **Subtitle Sync** | Auto Sync (detect & correct offset), Sync Now (manual ±offset), Fix RTL (right-to-left reordering), Fix Reversed Punctuation (Arabic punctuation correction). |
| **Subtitle Overlay** | Render subtitles over KSPlayer with custom font, size, color, background. |

### Phase 4 — Artwork & Extras

**Scope**: Enhanced artwork sources, automatic artwork rotation, intro skip.

| Task | Details |
|---|---|
| **Change Artwork Screen** | Browse artwork from: TMDB, MediUX, Apple TV, custom URL. |
| **Artwork Rotation** | Automatic rotation of multiple artworks every 5 minutes (configurable). |
| **IntroDB Integration** | Fetch intro timestamps from IntroDB. Skip-intro button overlay during playback. |
| **Outro Detection** | Optional: auto-advance to next episode when outro is detected. |

---

## Folder Structure

```
AuraTV/
├── SPEC.md
├── PROGRESS.md
├── AuraTV/
│   ├── AuraTVApp.swift
│   ├── ContentView.swift
│   ├── Assets.xcassets/
│   │   ├── Contents.json
│   │   └── AccentColor.colorset/
│   │       └── Contents.json
│   ├── Models/
│   │   ├── TMDBModels.swift
│   │   ├── WatchHistory.swift
│   │   ├── WatchlistItem.swift
│   │   └── AppSettings.swift
│   ├── Services/
│   │   └── TMDBService.swift
│   ├── ViewModels/
│   │   ├── HomeViewModel.swift
│   │   ├── MoviesViewModel.swift
│   │   ├── SeriesViewModel.swift
│   │   ├── DetailViewModel.swift
│   │   ├── SearchViewModel.swift
│   │   └── SettingsViewModel.swift
│   ├── Views/
│   │   ├── Home/
│   │   │   ├── HomeView.swift
│   │   │   ├── SpotlightCarouselView.swift
│   │   │   └── ContinueWatchingRow.swift
│   │   ├── Movies/
│   │   │   └── MoviesView.swift
│   │   ├── Series/
│   │   │   └── SeriesView.swift
│   │   ├── Detail/
│   │   │   ├── MovieDetailView.swift
│   │   │   └── SeriesDetailView.swift
│   │   ├── Search/
│   │   │   └── SearchView.swift
│   │   ├── Collections/
│   │   │   └── CollectionsView.swift
│   │   └── Settings/
│   │       └── SettingsView.swift
│   ├── Components/
│   │   ├── PosterCardView.swift
│   │   ├── EpisodeCardView.swift
│   │   ├── BadgeView.swift
│   │   ├── MediaRowView.swift
│   │   └── CastCardView.swift
│   └── Extensions/
│       ├── Color+Theme.swift
│       └── View+Focus.swift
└── AuraTV.xcodeproj/
    └── project.pbxproj
```

---

## Key Design Decisions

1. **tvOS 18+ minimum** — enables `TabView(.sidebarAdaptable)` for the native glass sidebar.
2. **SwiftData over Core Data** — simpler API, native Swift integration, automatic iCloud sync potential.
3. **Observable macro** — ViewModels use `@Observable` (iOS 17+ / tvOS 17+) for clean reactive updates.
4. **AsyncImage with caching** — TMDB images loaded via `AsyncImage` with URL cache.
5. **Modular views** — each screen is a self-contained SwiftUI view with its own ViewModel.
6. **No third-party UI libraries** — pure SwiftUI for maximum tvOS compatibility.
