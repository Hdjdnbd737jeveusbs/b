import SwiftUI
import SwiftData
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Setup via Phone (QR Code) Screen

struct PhoneQRSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var settingsViewModel: SettingsViewModel
    let onSaved: () -> Void

    @State private var server = LocalConfigServer()
    @FocusState private var isDoneFocused: Bool

    private let ciContext = CIContext()

    var body: some View {
        ZStack {
            Color.auraBackground.ignoresSafeArea()

            HStack(spacing: 56) {
                // LEFT: QR Code Card + URL
                VStack(spacing: 22) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.white)
                            .frame(width: 340, height: 340)
                            .shadow(color: .black.opacity(0.45), radius: 28, y: 12)

                        if let urlStr = server.setupURLString, let qrImage = generateQRCode(from: urlStr) {
                            Image(decorative: qrImage, scale: 1.0)
                                .interpolation(.none)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 292, height: 292)
                        } else {
                            ProgressView()
                                .scaleEffect(1.6)
                                .tint(.black)
                        }
                    }

                    VStack(spacing: 6) {
                        Text(server.setupURLString ?? "Starting local endpoint...")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.08), in: Capsule())

                        HStack(spacing: 8) {
                            Circle()
                                .fill(server.isRunning ? Color.green : Color.orange)
                                .frame(width: 9, height: 9)
                            Text(server.lastSavedSummary ?? server.statusMessage)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(server.savedSubmissionsCount > 0 ? Color.green : Color.auraSecondaryText)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .frame(width: 420)

                // RIGHT: Instructions + Live Status + Done Button
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Setup via Phone (QR Code)", systemImage: "qrcode.viewfinder")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)

                        Text("Scan with your phone camera to paste AIOStreams manifest URLs and API keys using your phone's keyboard. The local server stops automatically when you close this screen.")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineSpacing(4)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        statusRow(
                            title: "AIOStreams / Stremio",
                            value: settingsViewModel.aioStreamsUrl.isEmpty ? "Not Set" : "Configured",
                            isConfigured: !settingsViewModel.aioStreamsUrl.isEmpty
                        )
                        statusRow(
                            title: "TMDB API Key",
                            value: settingsViewModel.tmdbApiKey.isEmpty ? "Not Set" : "Configured",
                            isConfigured: !settingsViewModel.tmdbApiKey.isEmpty
                        )
                        statusRow(
                            title: "MDBList Ratings",
                            value: settingsViewModel.mdblistApiKey.isEmpty ? "Optional" : "Configured",
                            isConfigured: !settingsViewModel.mdblistApiKey.isEmpty
                        )
                        statusRow(
                            title: "AI Translation (\(settingsViewModel.aiTranslationProvider))",
                            value: settingsViewModel.aiTranslationApiKey.isEmpty ? "Optional" : "Configured",
                            isConfigured: !settingsViewModel.aiTranslationApiKey.isEmpty
                        )
                    }

                    if let err = server.errorMessage {
                        Text(err)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.orange)
                    }

                    Button {
                        server.stop()
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(isDoneFocused ? Color.black : Color.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 15)
                            .background(
                                Capsule().fill(isDoneFocused ? Color.white : Color.white.opacity(0.16))
                            )
                            .scaleEffect(isDoneFocused ? 1.05 : 1.0)
                            .animation(.easeOut(duration: 0.16), value: isDoneFocused)
                    }
                    .buttonStyle(AuraButtonStyle())
                    .focusEffectDisabled()
                    .focused($isDoneFocused)
                }
                .frame(maxWidth: 680, alignment: .leading)
            }
            .padding(70)
        }
        .onAppear {
            server.start(context: modelContext) {
                settingsViewModel.loadSettings(context: modelContext)
                onSaved()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isDoneFocused = true
            }
        }
        .onDisappear {
            server.stop()
        }
    }

    @ViewBuilder
    private func statusRow(title: String, value: String, isConfigured: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: isConfigured ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(isConfigured ? Color.green : Color.white.opacity(0.45))
                Text(value)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isConfigured ? Color.white : Color.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func generateQRCode(from text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        return ciContext.createCGImage(scaled, from: scaled.extent)
    }
}
