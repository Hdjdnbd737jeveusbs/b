import SwiftUI

// MARK: - Sync to a Line Sheet (Pick Currently Spoken Line for Exact Offset)

struct SyncToLineSheet: View {
    let cues: [AuraSubtitleCue]
    let currentTime: Double
    let currentOffset: Double
    let fixRTL: Bool
    let fixReversedPunctuation: Bool
    let onSelectCue: (AuraSubtitleCue) -> Void
    let onDismiss: () -> Void

    @FocusState private var focusedItem: LineFocusTarget?

    enum LineFocusTarget: Hashable {
        case cue(Int)
        case cancel
    }

    private var nearbyCues: [AuraSubtitleCue] {
        guard !cues.isEmpty else { return [] }
        let adjustedNow = currentTime - currentOffset
        let closestIndex = cues.enumerated().min(by: { lhs, rhs in
            abs(lhs.element.startTime - adjustedNow) < abs(rhs.element.startTime - adjustedNow)
        })?.offset ?? 0

        let start = max(0, closestIndex - 6)
        let end = min(cues.count - 1, closestIndex + 7)
        return Array(cues[start...end])
    }

    private var defaultCueId: Int? {
        let adjustedNow = currentTime - currentOffset
        return nearbyCues.min(by: {
            abs($0.startTime - adjustedNow) < abs($1.startTime - adjustedNow)
        })?.id
    }

    var body: some View {
        VStack(alignment: .trailing) {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sync to a Line")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Select the line being spoken right now to align timing instantly.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer()

                    Text("At \(formatTimestamp(currentTime))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.10), in: Capsule())
                }

                Divider().background(Color.white.opacity(0.12))

                if nearbyCues.isEmpty {
                    Text("No subtitle lines loaded for this track yet.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 6) {
                                ForEach(nearbyCues) { cue in
                                    cueRow(for: cue)
                                        .id(cue.id)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(maxHeight: 420)
                        .onAppear {
                            if let targetId = defaultCueId {
                                proxy.scrollTo(targetId, anchor: .center)
                            }
                        }
                    }
                }

                Divider().background(Color.white.opacity(0.10))

                HStack {
                    Button(action: onDismiss) {
                        Text("Cancel")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(focusedItem == .cancel ? Color.black : Color.white.opacity(0.82))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(focusedItem == .cancel ? Color.white : Color.white.opacity(0.10))
                            )
                    }
                    .buttonStyle(AuraButtonStyle())
                    .focusEffectDisabled()
                    .focused($focusedItem, equals: .cancel)

                    Spacer()

                    Text("Offset: \(SubtitleSyncEngine.formatOffset(currentOffset))")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(24)
            .frame(width: 580)
            .background(Color(red: 22 / 255, green: 24 / 255, blue: 30 / 255).opacity(0.95), in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.75), radius: 28, y: 12)
            .padding(.trailing, 70)
            .padding(.bottom, 64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if let targetId = defaultCueId {
                    focusedItem = .cue(targetId)
                } else {
                    focusedItem = .cancel
                }
            }
        }
    }

    @ViewBuilder
    private func cueRow(for cue: AuraSubtitleCue) -> some View {
        let isFocused = focusedItem == .cue(cue.id)
        let isCurrentlyActive = cue.isActive(at: currentTime, offset: currentOffset)
        let candidateOffset = currentTime - cue.startTime
        let displayLine = SubtitleProcessor.process(
            text: cue.text.replacingOccurrences(of: "\n", with: " "),
            isArabic: cue.isArabic,
            fixRTL: fixRTL,
            fixReversedPunctuation: fixReversedPunctuation
        )

        Button {
            onSelectCue(cue)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatTimestamp(cue.startTime))
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(isFocused ? Color.black.opacity(0.72) : Color.white.opacity(0.65))

                    Text(SubtitleSyncEngine.formatOffset(candidateOffset))
                        .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(isFocused ? Color.black.opacity(0.55) : (isCurrentlyActive ? Color.auraAccent : Color.white.opacity(0.42)))
                }
                .frame(width: 78, alignment: .leading)

                Text(displayLine)
                    .font(.system(size: 15, weight: isCurrentlyActive ? .semibold : .regular))
                    .foregroundStyle(isFocused ? Color.black : .white)
                    .lineLimit(2)
                    .multilineTextAlignment(cue.isArabic ? .trailing : .leading)
                    .frame(maxWidth: .infinity, alignment: cue.isArabic ? .trailing : .leading)

                if isCurrentlyActive {
                    Circle()
                        .fill(isFocused ? Color.black : Color.auraAccent)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isFocused ? Color.white : (isCurrentlyActive ? Color.white.opacity(0.11) : Color.white.opacity(0.04)))
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(AuraButtonStyle())
        .focusEffectDisabled()
        .focused($focusedItem, equals: .cue(cue.id))
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
