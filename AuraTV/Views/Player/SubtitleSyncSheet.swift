import SwiftUI

// MARK: - Subtitle Sync Panel (Right-Anchored Floating Popover Matching Video Reference)

struct SubtitleSyncSheet: View {
    @Binding var settings: SubtitleSyncSettings
    var isSyncing: Bool = false
    var statusMessage: String? = nil
    let onSyncNow: () -> Void
    let onDismiss: () -> Void

    @FocusState private var focusedItem: SyncControl?

    enum SyncControl: Hashable {
        case earlierSmall
        case laterSmall
        case earlierLarge
        case laterLarge
        case reset
        case autoSync
        case syncNow
        case fixRTL
        case fixPunctuation
        case done
    }

    var body: some View {
        VStack(alignment: .trailing) {
            Spacer()

            VStack(alignment: .leading, spacing: 18) {
                // Top Header Title
                Text("Subtitle Sync")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                // Large Offset on Left + 2-Line Muted Note on Right
                HStack(alignment: .center, spacing: 18) {
                    Text(SubtitleSyncEngine.formatOffset(settings.manualOffset))
                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Subtitles are shown at their original times.")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Saved for this file and subtitle. Playback keeps going.")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .lineLimit(1)

                    Spacer(minLength: 0)
                }

                // 5 Compact Offset Pills in One Row
                HStack(spacing: 8) {
                    syncPill(title: "− Earlier 0.1 s", control: .earlierSmall) {
                        settings.manualOffset = SubtitleSyncEngine.adjustOffset(current: settings.manualOffset, delta: -0.1)
                    }
                    syncPill(title: "+ Later 0.1 s", control: .laterSmall) {
                        settings.manualOffset = SubtitleSyncEngine.adjustOffset(current: settings.manualOffset, delta: 0.1)
                    }
                    syncPill(title: "-1 s", control: .earlierLarge) {
                        settings.manualOffset = SubtitleSyncEngine.adjustOffset(current: settings.manualOffset, delta: -1.0)
                    }
                    syncPill(title: "+1 s", control: .laterLarge) {
                        settings.manualOffset = SubtitleSyncEngine.adjustOffset(current: settings.manualOffset, delta: 1.0)
                    }
                    syncPill(title: "↺ Reset", control: .reset) {
                        settings.manualOffset = SubtitleSyncEngine.resetOffset()
                    }
                }

                Divider().background(Color.white.opacity(0.12))

                // Toggle & Action Rows
                VStack(alignment: .leading, spacing: 6) {
                    compactToggleRow(
                        title: "Auto Sync",
                        subtitle: "For this title only: align a subtitle that is early, late or drifting",
                        icon: "sparkles",
                        isOn: $settings.autoSyncEnabled,
                        control: .autoSync
                    )

                    compactActionRow(
                        title: isSyncing ? "Syncing..." : "Sync Now",
                        subtitle: "Uses the video's embedded English subtitle as the reference",
                        icon: "waveform.and.magnifyingglass",
                        isBusy: isSyncing,
                        control: .syncNow,
                        action: onSyncNow
                    )

                    Text("Matches the video's English subtitle: offset, frame rate and cuts")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.white.opacity(0.44))
                        .padding(.leading, 40)
                        .padding(.bottom, 4)

                    Divider().background(Color.white.opacity(0.10))

                    compactToggleRow(
                        title: "Fix RTL",
                        subtitle: "For this title only: punctuation at the end of Arabic lines, as in Subtitle Edit.",
                        icon: "text.alignright",
                        isOn: $settings.fixRTL,
                        control: .fixRTL
                    )

                    compactToggleRow(
                        title: "Fix Reversed Punctuation",
                        subtitle: "For this title only: punctuation fixed at the wrong end of Arabic lines.",
                        icon: "arrow.left.arrow.right",
                        isOn: $settings.fixReversedPunctuation,
                        control: .fixPunctuation
                    )
                }

                // Bottom-Left Subtle Done Button
                HStack {
                    Button(action: onDismiss) {
                        Text("Done")
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(focusedItem == .done ? Color.black : Color.white.opacity(0.75))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(focusedItem == .done ? Color.white : Color.clear)
                            )
                            .scaleEffect(focusedItem == .done ? 1.04 : 1.0)
                            .animation(.easeOut(duration: 0.14), value: focusedItem)
                    }
                    .buttonStyle(AuraButtonStyle())
                    .focusEffectDisabled()
                    .focused($focusedItem, equals: .done)

                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(24)
            .frame(width: 820)
            .background(Color(red: 22 / 255, green: 24 / 255, blue: 30 / 255).opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.75), radius: 28, y: 12)
            .padding(.trailing, 90)
            .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .defaultFocus($focusedItem, .earlierSmall)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                focusedItem = .earlierSmall
            }
        }
    }

    // MARK: - Compact Sync Pill

    @ViewBuilder
    private func syncPill(title: String, control: SyncControl, action: @escaping () -> Void) -> some View {
        let isFocused = focusedItem == control

        Button(action: action) {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isFocused ? Color.black : Color.white.opacity(0.9))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 13)
                .background(isFocused ? Color.white : Color.white.opacity(0.08), in: Capsule())
                .scaleEffect(isFocused ? 1.04 : 1.0)
                .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedItem, equals: control)
    }

    // MARK: - Compact Toggle Row

    @ViewBuilder
    private func compactToggleRow(
        title: String,
        subtitle: String,
        icon: String,
        isOn: Binding<Bool>,
        control: SyncControl
    ) -> some View {
        let isFocused = focusedItem == control

        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(isFocused ? Color.black : Color.white.opacity(0.85))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(isFocused ? Color.black : Color.white)
                    Text(subtitle)
                        .font(.system(size: 18))
                        .foregroundStyle(isFocused ? Color.black.opacity(0.68) : Color.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                Text(isOn.wrappedValue ? "On" : "Off")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(isFocused ? Color.black.opacity(0.75) : Color.white.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isFocused ? Color.white : Color.clear)
            )
            .scaleEffect(isFocused ? 1.01 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedItem, equals: control)
    }

    // MARK: - Compact Action Row

    @ViewBuilder
    private func compactActionRow(
        title: String,
        subtitle: String,
        icon: String,
        isBusy: Bool,
        control: SyncControl,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = focusedItem == control

        Button(action: action) {
            HStack(spacing: 12) {
                if isBusy {
                    ProgressView()
                        .tint(isFocused ? .black : .white)
                        .scaleEffect(0.75)
                        .frame(width: 22)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(isFocused ? Color.black : Color.white.opacity(0.85))
                        .frame(width: 22)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(isFocused ? Color.black : Color.white)
                    Text(subtitle)
                        .font(.system(size: 18))
                        .foregroundStyle(isFocused ? Color.black.opacity(0.68) : Color.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                Image(systemName: "arrow.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isFocused ? Color.black.opacity(0.7) : Color.white.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isFocused ? Color.white : Color.clear)
            )
            .scaleEffect(isFocused ? 1.01 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedItem, equals: control)
    }
}
