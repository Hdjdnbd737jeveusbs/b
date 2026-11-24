import SwiftUI
import SwiftData

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SettingsViewModel()
    @State private var showSavedAlert: Bool = false
    @State private var exportSuccess: Bool = false

    var body: some View {
        ZStack {
            Color.auraBackground.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 36) {
                    // Title Header
                    Text("Settings")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 50)
                        .padding(.top, 24)

                    // Section 1: TMDB API Configuration
                    settingsSection(title: "TMDB API Configuration") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("TMDB API Key (v3)")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)

                            SecureField("Enter your TMDB API Key", text: $viewModel.tmdbApiKey)
                                .font(.system(size: 20))
                                .padding(16)
                                .background(Color.auraSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            Text("Required for movie and series metadata, artwork, and search.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.auraSecondaryText)
                        }
                    }

                    // Section 2: Streaming Source (Phase 2 Preview)
                    settingsSection(title: "Streaming Source") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("AIOStreams Manifest URL")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)

                            TextField("https://aiostreams.example.com/manifest.json", text: $viewModel.aioStreamsUrl)
                                .font(.system(size: 20))
                                .padding(16)
                                .background(Color.auraSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            Text("Stremio-compatible streaming manifest URL (active in Phase 2).")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.auraSecondaryText)
                        }
                    }

                    // Section 3: Playback & Language Preferences
                    settingsSection(title: "Preferences") {
                        VStack(spacing: 20) {
                            // Quality
                            HStack {
                                Text("Preferred Quality")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(.white)
                                Spacer()
                                Picker("Quality", selection: $viewModel.preferredQuality) {
                                    ForEach(SettingsViewModel.qualityOptions, id: \.self) { quality in
                                        Text(quality).tag(quality)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 360)
                            }

                            Divider().background(Color.white.opacity(0.1))

                            // Subtitle Language
                            HStack {
                                Text("Default Subtitle Language")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(.white)
                                Spacer()
                                Picker("Subtitle Language", selection: $viewModel.subtitleLanguage) {
                                    Text("Arabic (ar)").tag("ar")
                                    Text("English (en)").tag("en")
                                    Text("Spanish (es)").tag("es")
                                    Text("French (fr)").tag("fr")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 420)
                            }
                        }
                        .padding(20)
                        .background(Color.auraSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // Section 4: Subtitle Providers & Arabic Configuration (Phase 3)
                    settingsSection(title: "Subtitle Providers & Arabic Engine") {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("SubDL API Key (Optional)")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                SecureField("SubDL API Key", text: $viewModel.subdlApiKey)
                                    .font(.system(size: 20))
                                    .padding(16)
                                    .background(Color.auraSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                Text("Enables comprehensive Arabic and international subtitles from SubDL.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.auraSecondaryText)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("OpenSubtitles.com API Key (Optional)")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                SecureField("OpenSubtitles REST API Key", text: $viewModel.openSubtitlesApiKey)
                                    .font(.system(size: 20))
                                    .padding(16)
                                    .background(Color.auraSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                Text("Wyzie subtitles require no key and are enabled automatically.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.auraSecondaryText)
                            }

                            VStack(spacing: 16) {
                                Toggle(isOn: $viewModel.fixArabicRTL) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Fix Arabic RTL Alignment & Direction")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Text("Forces proper right-to-left layout for Arabic text lines.")
                                            .font(.system(size: 14))
                                            .foregroundStyle(Color.auraSecondaryText)
                                    }
                                }

                                Divider().background(Color.white.opacity(0.1))

                                Toggle(isOn: $viewModel.fixReversedPunctuation) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Fix Reversed Punctuation")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Text("Corrects periods, question marks, and dashes misplaced at line ends.")
                                            .font(.system(size: 14))
                                            .foregroundStyle(Color.auraSecondaryText)
                                    }
                                }
                            }
                            .padding(20)
                            .background(Color.auraSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    // Section 4: Backup & Data Management
                    settingsSection(title: "Local SwiftData Backup") {
                        VStack(spacing: 16) {
                            HStack(spacing: 20) {
                                Button(action: {
                                    if let data = viewModel.exportWatchHistory(context: modelContext) {
                                        exportSuccess = true
                                    }
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("Export Watch History (JSON)")
                                    }
                                    .font(.system(size: 18, weight: .semibold))
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 14)
                                    .background(Color.white.opacity(0.15))
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                                }

                                Button(action: {
                                    // Trigger import if export data is cached
                                    if let data = viewModel.exportData {
                                        viewModel.importWatchHistory(data: data, context: modelContext)
                                    }
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "square.and.arrow.down")
                                        Text("Import Watch History (JSON)")
                                    }
                                    .font(.system(size: 18, weight: .semibold))
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 14)
                                    .background(Color.white.opacity(0.15))
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                                }
                            }

                            if exportSuccess {
                                Text("✅ Watch history successfully exported to JSON backup!")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.green)
                            }
                        }
                    }

                    // Section 5: Save Settings Button
                    Button(action: {
                        viewModel.saveSettings(context: modelContext)
                        showSavedAlert = true
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save Settings")
                        }
                        .font(.system(size: 22, weight: .bold))
                        .padding(.horizontal, 48)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 50)

                    // About section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AuraTV v1.0.0 (tvOS 18)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("Native Apple TV 4K Streaming Experience")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.auraSecondaryText)
                    }
                    .padding(.horizontal, 50)
                    .padding(.top, 20)

                    Spacer().frame(height: 60)
                }
            }
        }
        .task {
            viewModel.loadSettings(context: modelContext)
        }
        .alert("Settings Saved", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your TMDB API key and preferences have been persisted.")
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            content()
        }
        .padding(.horizontal, 50)
    }
}
