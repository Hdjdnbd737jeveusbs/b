import SwiftUI

// MARK: - Stream Picker Sheet (Dark Cinema Glassmorphic Stream Selector)

struct StreamPickerSheet: View {
    let title: String
    let streams: [StremioStream]
    var selectedStream: StremioStream? = nil
    var preferredQuality: String = "4K"
    let onSelect: (StremioStream) -> Void
    let onDismiss: () -> Void

    @FocusState private var focusedControl: PickerFocus?

    enum PickerFocus: Hashable {
        case autoBest
        case stream(String)
        case cancel
    }

    var body: some View {
        ZStack {
            Color.auraBackground.opacity(0.94)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 26) {
                // Header + Quick Play Best Preferred Quality CTA
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Select Stream")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)

                        Text(title)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    Spacer()

                    if let best = AIOStreamsService.shared.bestStream(matching: preferredQuality, in: streams) {
                        Button {
                            onSelect(best)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "bolt.fill")
                                Text("Play Best (\(preferredQuality))")
                            }
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(Color.white, in: Capsule())
                            .scaleEffect(focusedControl == .autoBest ? 1.06 : 1.0)
                            .animation(.easeOut(duration: 0.16), value: focusedControl)
                        }
                        .buttonStyle(AuraButtonStyle())
                        .focusEffectDisabled()
                        .focused($focusedControl, equals: .autoBest)
                    }
                }

                // Stream list grouped by resolution
                streamsList

                Button(action: onDismiss) {
                    Text("Close")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(focusedControl == .cancel ? .black : .white)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 13)
                        .background(focusedControl == .cancel ? Color.white : Color.white.opacity(0.14), in: Capsule())
                        .scaleEffect(focusedControl == .cancel ? 1.05 : 1.0)
                        .animation(.easeOut(duration: 0.16), value: focusedControl)
                }
                .buttonStyle(AuraButtonStyle())
                .focusEffectDisabled()
                .focused($focusedControl, equals: .cancel)
            }
            .padding(65)
        }
    }

    @ViewBuilder
    private var streamsList: some View {
        let grouped = groupedByResolution()

        if streams.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "play.slash")
                    .font(.system(size: 52))
                    .foregroundStyle(.white.opacity(0.3))
                Text("No Streams Available")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text("Configure a valid AIOStreams manifest URL in Settings → Servers & Accounts.")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.auraSecondaryText)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(grouped, id: \.resolution) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(group.resolution.displayName)
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)

                                Text("\(group.streams.count)")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.42))
                            }

                            ForEach(group.streams) { stream in
                                StreamRowView(
                                    stream: stream,
                                    isActive: selectedStream?.id == stream.id,
                                    isFocused: focusedControl == .stream(stream.id),
                                    onSelect: { onSelect(stream) }
                                )
                                .focused($focusedControl, equals: .stream(stream.id))
                            }
                        }
                    }
                }
            }
        }
    }

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
    let isActive: Bool
    let isFocused: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(isFocused ? .black : .green)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if let provider = stream.parsedInfo.providerName, !provider.isEmpty {
                        Text(provider)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(isFocused ? Color.black : Color.white)
                            .lineLimit(1)
                    }

                    let details = stream.displayDetails
                    if !details.isEmpty {
                        Text(details)
                            .font(.system(size: 14))
                            .foregroundStyle(isFocused ? Color.black.opacity(0.75) : Color.white.opacity(0.65))
                            .lineLimit(2)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    if stream.parsedInfo.isCached {
                        BadgeView(text: "⚡ Cached", style: isFocused ? .darkPill : .filled, fontSize: 12)
                    }
                    if let release = stream.parsedInfo.releaseType {
                        BadgeView(text: release, style: isFocused ? .darkPill : .outlined, fontSize: 12)
                    }
                    if let hdr = stream.parsedInfo.hdrType {
                        BadgeView(text: hdr.displayName, style: isFocused ? .darkPill : .outlined, fontSize: 12)
                    }
                    if let audio = stream.parsedInfo.audioCodec {
                        BadgeView(text: audio, style: isFocused ? .darkPill : .outlined, fontSize: 12)
                    }
                    if let size = stream.parsedInfo.fileSize {
                        Text(size)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isFocused ? Color.black.opacity(0.8) : Color.white.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isFocused ? Color.white : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.1), lineWidth: isFocused ? 2.5 : 1)
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.16), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
    }
}
