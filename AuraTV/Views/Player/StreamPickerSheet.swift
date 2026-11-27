import SwiftUI

// MARK: - Stream Picker Sheet (Dark Cinema Glassmorphic Stream Selector)

struct StreamPickerSheet: View {
    let title: String
    let streams: [StremioStream]
    var selectedStream: StremioStream? = nil
    var preferredQuality: String = "4K"
    var isLoadingMore: Bool = false
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
            Color.auraBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 26) {
                // Header + Quick Play Best Preferred Quality CTA
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 16) {
                            Text("Select Stream")
                                .font(.system(size: 48, weight: .bold))
                                .foregroundStyle(.white)

                            if isLoadingMore {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(.white)
                                    Text("Loading more addons...")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.72))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.auraCardSurface, in: Capsule())
                            }
                        }

                        Text(title)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    Spacer()

                    if let first = streams.first(where: { $0.url != nil && !($0.url?.isEmpty ?? true) }) {
                        Button {
                            onSelect(first)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "bolt.fill")
                                Text("Play First Stream")
                            }
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 16)
                            .background(Color.white, in: Capsule())
                            .scaleEffect(focusedControl == .autoBest ? 1.05 : 1.0)
                            .animation(.easeOut(duration: 0.14), value: focusedControl)
                        }
                        .buttonStyle(AuraButtonStyle())
                        .focusEffectDisabled()
                        .focused($focusedControl, equals: .autoBest)
                    }
                }

                // Stream list (LazyVStack for locked 60fps scrolling)
                streamsList

                Button(action: onDismiss) {
                    Text("Close")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(focusedControl == .cancel ? .black : .white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 15)
                        .background(focusedControl == .cancel ? Color.white : Color.auraCardSurface, in: Capsule())
                        .scaleEffect(focusedControl == .cancel ? 1.04 : 1.0)
                        .animation(.easeOut(duration: 0.14), value: focusedControl)
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
        if streams.isEmpty {
            VStack(spacing: 14) {
                Spacer()
                if isLoadingMore {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Fetching Streams...")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "play.slash")
                        .font(.system(size: 54))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No Streams Available")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Configure a valid AIOStreams, Stremio, or Nuvio manifest URL in Settings → Servers & Accounts.")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.auraSecondaryText)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(streams.enumerated()), id: \.offset) { index, stream in
                        StreamRowView(
                            stream: stream,
                            parsed: stream.parsedInfo,
                            isActive: selectedStream?.id == stream.id,
                            isFocused: focusedControl == .stream("\(index)_\(stream.id)"),
                            onSelect: { onSelect(stream) }
                        )
                        .equatable()
                        .focused($focusedControl, equals: .stream("\(index)_\(stream.id)"))
                    }
                }
            }
        }
    }
}

// MARK: - Stream Row View

private struct StreamRowView: View, Equatable {
    let stream: StremioStream
    let parsed: ParsedStreamInfo
    let isActive: Bool
    let isFocused: Bool
    let onSelect: () -> Void

    static func == (lhs: StreamRowView, rhs: StreamRowView) -> Bool {
        lhs.stream.id == rhs.stream.id &&
        lhs.parsed == rhs.parsed &&
        lhs.isActive == rhs.isActive &&
        lhs.isFocused == rhs.isFocused
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 18) {
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(isFocused ? .black : .green)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if let provider = parsed.providerName, !provider.isEmpty {
                        Text(provider)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(isFocused ? Color.black : Color.white)
                            .lineLimit(1)
                    }

                    let details = stream.displayDetails
                    if !details.isEmpty {
                        Text(details)
                            .font(.system(size: 19))
                            .foregroundStyle(isFocused ? Color.black.opacity(0.75) : Color.white.opacity(0.68))
                            .lineLimit(2)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    if parsed.resolution != .unknown {
                        BadgeView(text: parsed.resolution.displayName, style: isFocused ? .darkPill : .filled, fontSize: 13)
                    }
                    if parsed.isCached {
                        BadgeView(text: "⚡ Cached", style: isFocused ? .darkPill : .filled, fontSize: 13)
                    }
                    if let release = parsed.releaseType {
                        BadgeView(text: release, style: isFocused ? .darkPill : .outlined, fontSize: 13)
                    }
                    if let hdr = parsed.hdrType {
                        BadgeView(text: hdr.displayName, style: isFocused ? .darkPill : .outlined, fontSize: 13)
                    }
                    if let audio = parsed.audioCodec {
                        BadgeView(text: audio, style: isFocused ? .darkPill : .outlined, fontSize: 13)
                    }
                    if let size = parsed.fileSize {
                        Text(size)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isFocused ? Color.black.opacity(0.8) : Color.white.opacity(0.65))
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isFocused ? Color.white : Color.auraCardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isFocused ? Color.white : Color.white.opacity(0.08), lineWidth: isFocused ? 2.5 : 1)
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
    }
}
