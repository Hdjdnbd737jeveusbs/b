import SwiftUI

// MARK: - Subtitle Sync Sheet (Matches Reference Screenshot)

struct SubtitleSyncSheet: View {
    @Binding var settings: SubtitleSyncSettings
    let onSyncNow: () -> Void
    let onDismiss: () -> Void

    @FocusState private var focusedItem: SyncControl?

    enum SyncControl: Hashable {
        case earlier01
        case later01
        case earlier1
        case later1
        case reset
        case autoSync
        case syncNow
        case fixRTL
        case fixPunctuation
        case done
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                // Header
                Text("Subtitle Sync")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                // Large offset display
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(SubtitleSyncEngine.formatOffset(settings.manualOffset))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(settings.manualOffset == 0 ? "Subtitles are shown at their original times." : "Subtitles adjusted by offset.")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.85))

                        Text("Saved for this file and subtitle. Playback keeps going.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.auraSecondaryText)
                    }
                }

                // Offset buttons row (- Earlier 0.1 s, + Later 0.1 s, -1 s, +1 s, Reset)
                HStack(spacing: 12) {
                    offsetButton(title: "—  Earlier 0.1 s", control: .earlier01) {
                        settings.manualOffset = SubtitleSyncEngine.adjustOffset(current: settings.manualOffset, delta: -0.1)
                    }

                    offsetButton(title: "+  Later 0.1 s", control: .later01) {
                        settings.manualOffset = SubtitleSyncEngine.adjustOffset(current: settings.manualOffset, delta: 0.1)
                    }

                    offsetButton(title: "—1 s", control: .earlier1) {
                        settings.manualOffset = SubtitleSyncEngine.adjustOffset(current: settings.manualOffset, delta: -1.0)
                    }

                    offsetButton(title: "+1 s", control: .later1) {
                        settings.manualOffset = SubtitleSyncEngine.adjustOffset(current: settings.manualOffset, delta: 1.0)
                    }

                    offsetButton(title: "↺ Reset", control: .reset) {
                        settings.manualOffset = SubtitleSyncEngine.resetOffset()
                    }
                }

                Divider().background(Color.white.opacity(0.15))

                // Option rows
                VStack(spacing: 14) {
                    // Auto Sync
                    toggleRow(
                        title: "Auto Sync",
                        subtitle: "For this title only: align a subtitle that is early, late or drifting",
                        icon: "sparkles",
                        isOn: $settings.autoSyncEnabled,
                        control: .autoSync
                    )

                    // Sync Now
                    actionRow(
                        title: "Sync Now",
                        subtitle: "Uses the video's embedded English subtitle as the reference",
                        note: "Matches the video's English subtitle: offset, frame rate and cuts",
                        icon: "sparkles",
                        control: .syncNow,
                        action: onSyncNow
                    )

                    // Fix RTL
                    toggleRow(
                        title: "Fix RTL",
                        subtitle: "For this title only: punctuation at the end of Arabic lines, as Subtitle Edit fix...",
                        icon: "text.alignright",
                        isOn: $settings.fixRTL,
                        control: .fixRTL
                    )

                    // Fix Reversed Punctuation
                    toggleRow(
                        title: "Fix Reversed Punctuation",
                        subtitle: "For this title only: punctuation typed at the wrong end of Arabic lines move...",
                        icon: "arrow.left.arrow.right",
                        isOn: $settings.fixReversedPunctuation,
                        control: .fixPunctuation
                    )
                }

                Spacer().frame(height: 10)

                // Done button
                Button(action: onDismiss) {
                    Text("Done")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .focused($focusedItem, equals: .done)
            }
            .padding(40)
            .frame(width: 820)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(white: 0.12))
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.6), radius: 24, x: 0, y: 10)
        }
    }

    // MARK: - Button Helpers

    @ViewBuilder
    private func offsetButton(title: String, control: SyncControl, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(focusedItem == control ? Color.white.opacity(0.3) : Color.white.opacity(0.12))
                )
                .scaleEffect(focusedItem == control ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: focusedItem)
        }
        .buttonStyle(.plain)
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

        Button(action: { isOn.wrappedValue.toggle() }) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isFocused ? Color.black : Color.white)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isFocused ? Color.black : Color.white)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(isFocused ? Color.black.opacity(0.7) : Color.auraSecondaryText)
                        .lineLimit(1)
                }

                Spacer()

                Text(isOn.wrappedValue ? "On" : "Off")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isFocused ? Color.black : (isOn.wrappedValue ? Color.white : Color.auraSecondaryText))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isFocused ? Color.white : Color.white.opacity(0.06))
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($focusedItem, equals: control)
    }

    @ViewBuilder
    private func actionRow(
        title: String,
        subtitle: String,
        note: String,
        icon: String,
        control: SyncControl,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = focusedItem == control

        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 16) {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(isFocused ? Color.black : Color.white)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isFocused ? Color.black : Color.white)
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(isFocused ? Color.black.opacity(0.7) : Color.auraSecondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isFocused ? Color.black : Color.white.opacity(0.7))
                }

                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(isFocused ? Color.black.opacity(0.6) : Color.auraSecondaryText.opacity(0.7))
                    .padding(.leading, 46)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isFocused ? Color.white : Color.white.opacity(0.06))
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($focusedItem, equals: control)
    }
}
