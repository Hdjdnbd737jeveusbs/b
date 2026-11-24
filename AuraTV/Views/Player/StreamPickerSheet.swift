import SwiftUI

// MARK: - Stream Picker Sheet

struct StreamPickerSheet: View {
    let title: String
    let streams: [StremioStream]
    let onSelect: (StremioStream) -> Void
    let onDismiss: () -> Void

    @FocusState private var focusedStreamId: String?

    var body: some View {
        ZStack {
            // Dark blurred background
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerSection

                // Stream list grouped by resolution
                streamsList

                // Cancel button
                cancelButton
            }
            .padding(60)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Stream")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)

            Text(title)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Streams List

    @ViewBuilder
    private var streamsList: some View {
        let grouped = groupedByResolution()

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(grouped, id: \.resolution) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        // Resolution header
                        HStack(spacing: 10) {
                            Text(group.resolution.displayName)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)

                            Text("\(group.streams.count) stream\(group.streams.count == 1 ? "" : "s")")
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        // Stream rows
                        ForEach(group.streams) { stream in
                            StreamRowView(
                                stream: stream,
                                isFocused: focusedStreamId == stream.id,
                                onSelect: { onSelect(stream) }
                            )
                            .focused($focusedStreamId, equals: stream.id)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cancel Button

    @ViewBuilder
    private var cancelButton: some View {
        Button(action: onDismiss) {
            Text("Cancel")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grouping Helper

    private func groupedByResolution() -> [(resolution: StreamResolution, streams: [StremioStream])] {
        let grouped = Dictionary(grouping: streams) { $0.parsedInfo.resolution }
        let order: [StreamResolution] = [.uhd4k, .fhd1080p, .hd720p, .sd480p, .unknown]
        return order.compactMap { res in
            guard let group = grouped[res], !group.isEmpty else { return nil }
            return (resolution: res, streams: group)
        }
    }
}

// MARK: - Stream Row View

private struct StreamRowView: View {
    let stream: StremioStream
    let isFocused: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Left side: Provider & metadata
                VStack(alignment: .leading, spacing: 6) {
                    // Provider name
                    if let provider = stream.parsedInfo.providerName, !provider.isEmpty {
                        Text(provider)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    // Stream title / details
                    if let title = stream.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                    }
                }

                Spacer()

                // Right side: Badges
                HStack(spacing: 8) {
                    // Cached badge
                    if stream.parsedInfo.isCached {
                        StreamBadge(text: "⚡ Cached", color: .green)
                    }

                    // HDR badge
                    if let hdr = stream.parsedInfo.hdrType {
                        StreamBadge(text: hdr.displayName, color: .orange)
                    }

                    // Audio badge
                    if let audio = stream.parsedInfo.audioCodec {
                        StreamBadge(text: audio, color: .blue)
                    }

                    // File size
                    if let size = stream.parsedInfo.fileSize ?? stream.behaviorHints?.formattedSize {
                        Text(size)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isFocused ? Color.white.opacity(0.2) : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isFocused ? Color.white.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stream Badge

private struct StreamBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
