import SwiftUI

// MARK: - Live Playback Stats Overlay (Top-Right Floating Telemetry HUD)

struct PlaybackStatsOverlay: View {
    let stats: PlaybackStats
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)

                Text("Playback Stats")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.auraText)

                Spacer()

                Text(stats.activeEngine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.92), in: Capsule())
            }

            Divider().background(Color.white.opacity(0.14))

            statSectionHeader("VIDEO")
            statRow(label: "Codec / Res", value: "\(stats.videoCodec) · \(stats.resolution)")
            statRow(label: "Dynamic Range", value: stats.dynamicRange)
            statRow(label: "Observed FPS", value: stats.observedFPS)
            statRow(label: "Dropped Frames", value: "\(stats.droppedFrames)")

            Divider().background(Color.white.opacity(0.10))

            statSectionHeader("AUDIO")
            statRow(label: "Codec", value: stats.audioCodec)
            statRow(label: "Channels / Rate", value: "\(stats.audioChannels) · \(stats.audioBitrate)")

            Divider().background(Color.white.opacity(0.10))

            statSectionHeader("STREAM & SYNC")
            statRow(label: "Forward Buffer", value: stats.forwardBuffer)
            statRow(label: "Throughput", value: stats.throughput)
            statRow(label: "A/V Sync Gap", value: stats.avSyncGap)
        }
        .padding(18)
        .frame(width: 390)
        .background(Color(red: 16 / 255, green: 19 / 255, blue: 26 / 255).opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.auraGlassBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.6), radius: 20, y: 8)
    }

    private func statSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Color.auraSecondaryText)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}
