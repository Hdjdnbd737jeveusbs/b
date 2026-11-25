import SwiftUI

// MARK: - Subtitle Sync & Arabic Engine Glass Panel

struct SubtitleSyncSheet: View {
    @Binding var settings: SubtitleSyncSettings
    var isSyncing: Bool = false
    var statusMessage: String? = nil
    let onSyncNow: () -> Void
    let onDismiss: () -> Void

    @FocusState private var focusedItem: SyncControl?

    enum SyncControl: Hashable {
        case minus500
        case minus100
        case plus100
        case plus500
        case reset
        case autoSync
        case syncNow
        case fixRTL
        case fixPunctuation
        case done
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header + Live Offset Display
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Subtitle Sync")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)

                    Text(statusMessage ?? (settings.manualOffset == 0
                        ? "Subtitles are shown at their original times."
                        : "Live offset active — persisted for future titles."))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }

                Spacer()

                Text(SubtitleSyncEngine.formatOffset(settings.manualOffset))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            // Manual Sync Offset Buttons (-500ms, -100ms, +100ms, +500ms, Reset 0.0s)
            HStack(spacing: 12) {
                offsetButton(title: "-500ms", control: .minus500) {
                    settings.manualOffset = SubtitleSyncEngine.adjustOffset(current: settings.manualOffset, delta: -0.5)
                }

                offsetButton(title: "-100ms", control: .minus100) {
                    settings.manualOffset = SubtitleSyncEngine.adjustOffset(current: settings.manualOffset, delta: -0.1)
                }

                offsetButton(title: "+100ms", control: .plus100) {
                    settings.manualOffset = SubtitleSyncEngine.adjustOffset(current: settings.manualOffset, delta: 0.1)
                }

                offsetButton(title: "+500ms", control: .plus500) {
                    settings.manualOffset = SubtitleSyncEngine.adjustOffset(current: settings.manualOffset, delta: 0.5)
                }

                offsetButton(title: "Reset 0.0s", control: .reset) {
                    settings.manualOffset = SubtitleSyncEngine.resetOffset()
                }
            }

            Divider().background(Color.white.opacity(0.14))

            // Auto Sync & Arabic Engine Controls
            VStack(spacing: 12) {
                toggleRow(
                    title: "Auto Sync",
                    subtitle: "Aligns early, late, or drifting subtitles automatically when loaded",
                    icon: "sparkles",
                    isOn: $settings.autoSyncEnabled,
                    control: .autoSync
                )

                actionRow(
                    title: isSyncing ? "Syncing Subtitles..." : "Sync Now",
                    subtitle: "Uses embedded or English reference subtitle timestamps",
                    icon: "waveform.and.magnifyingglass",
                    isBusy: isSyncing,
                    control: .syncNow,
                    action: onSyncNow
                )

                toggleRow(
                    title: "Fix RTL",
                    subtitle: "Embeds Arabic lines with strict RTL directional markers (RLE / ALM / RLM)",
                    icon: "text.alignright",
                    isOn: $settings.fixRTL,
                    control: .fixRTL
                )

                toggleRow(
                    title: "Fix Reversed Punctuation",
                    subtitle: "Fixes periods, question marks, dashes, and brackets on Arabic lines",
                    icon: "arrow.left.arrow.right",
                    isOn: $settings.fixReversedPunctuation,
                    control: .fixPunctuation
                )
            }

            // Done Button
            Button(action: onDismiss) {
                Text("Done")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(focusedItem == .done ? Color.white : .clear, lineWidth: 2.5)
                            .padding(-4)
                    )
                    .scaleEffect(focusedItem == .done ? 1.03 : 1.0)
                    .animation(.easeOut(duration: 0.16), value: focusedItem)
            }
            .buttonStyle(AuraButtonStyle())
            .focusEffectDisabled()
            .focused($focusedItem, equals: .done)
        }
        .padding(36)
        .frame(width: 820)
        .background(Color.auraSurface.opacity(0.95), in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.75), radius: 28, y: 12)
        .defaultFocus($focusedItem, .syncNow)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func offsetButton(title: String, control: SyncControl, action: @escaping () -> Void) -> some View {
        let isFocused = focusedItem == control

        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isFocused ? Color.black : Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isFocused ? Color.white : Color.white.opacity(0.12), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(isFocused ? 1.0 : 0.2), lineWidth: 1)
                )
                .scaleEffect(isFocused ? 1.06 : 1.0)
                .animation(.easeOut(duration: 0.16), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedItem, equals: control)
    }

    @ViewBuilder
    private func toggleRow(
        title: String,
        subtitle: String,
        icon: String,
        isOn: Binding<Bool>,
        control: SyncControl
    ) -> some View {
        let isFocused = focusedItem == control

        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isFocused ? Color.black : Color.white)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isFocused ? Color.black : Color.white)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(isFocused ? Color.black.opacity(0.7) : Color.auraSecondaryText)
                        .lineLimit(1)
                }

                Spacer()

                Text(isOn.wrappedValue ? "On" : "Off")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isFocused ? Color.black : (isOn.wrappedValue ? Color.white : Color.auraSecondaryText))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(isFocused ? Color.black.opacity(0.12) : Color.white.opacity(isOn.wrappedValue ? 0.16 : 0.06))
                    )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isFocused ? Color.white : Color.white.opacity(0.06))
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.16), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedItem, equals: control)
    }

    @ViewBuilder
    private func actionRow(
        title: String,
        subtitle: String,
        icon: String,
        isBusy: Bool,
        control: SyncControl,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = focusedItem == control

        Button(action: action) {
            HStack(spacing: 16) {
                if isBusy {
                    ProgressView()
                        .tint(isFocused ? Color.black : Color.white)
                        .frame(width: 28)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(isFocused ? Color.black : Color.white)
                        .frame(width: 28)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isFocused ? Color.black : Color.white)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(isFocused ? Color.black.opacity(0.7) : Color.auraSecondaryText)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isFocused ? Color.black : Color.white.opacity(0.75))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isFocused ? Color.white : Color.white.opacity(0.08))
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.16), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedItem, equals: control)
    }
}
