import Foundation

// MARK: - Subtitle Sync Engine

final class SubtitleSyncEngine {

    // MARK: - Manual Offset Adjustment

    static func adjustOffset(current: Double, delta: Double) -> Double {
        let newOffset = current + delta
        // Round to 2 decimal places to avoid floating point errors
        return (newOffset * 100).rounded() / 100
    }

    static func resetOffset() -> Double {
        return 0.0
    }

    // MARK: - Auto Sync Engine (Timestamp Correlation)

    /// Aligns external target cues against a reference subtitle track (e.g. embedded English track).
    /// Uses timestamp correlation and median clustering to determine the optimal timing offset in seconds.
    static func calculateAutoSyncOffset(
        targetCues: [AuraSubtitleCue],
        referenceCues: [AuraSubtitleCue],
        searchWindowSeconds: TimeInterval = 15.0
    ) -> Double? {
        guard !targetCues.isEmpty, !referenceCues.isEmpty else { return nil }

        var deltas: [TimeInterval] = []

        // Compare first 80 dialogue events for fast and reliable correlation
        let targetSample = Array(targetCues.prefix(80))

        for target in targetSample {
            // Find closest reference cue within the search window
            var closestDelta: TimeInterval?
            var smallestDistance = searchWindowSeconds

            for reference in referenceCues {
                let diff = reference.startTime - target.startTime
                let distance = abs(diff)

                if distance < smallestDistance {
                    smallestDistance = distance
                    closestDelta = diff
                }
            }

            if let delta = closestDelta {
                deltas.append(delta)
            }
        }

        guard !deltas.isEmpty else { return nil }

        // Find the mode / dense cluster of deltas within 0.25 second buckets
        let bucketSize = 0.25
        var bucketCounts: [Int: [TimeInterval]] = [:]

        for delta in deltas {
            let bucketIndex = Int((delta / bucketSize).rounded())
            bucketCounts[bucketIndex, default: []].append(delta)
        }

        // Find bucket with highest number of matching cues
        guard let bestBucket = bucketCounts.max(by: { $0.value.count < $1.value.count }),
              bestBucket.value.count >= 3 else {
            // Fallback to median
            let sorted = deltas.sorted()
            let median = sorted[sorted.count / 2]
            return (median * 100).rounded() / 100
        }

        // Average of the best cluster
        let clusterAverage = bestBucket.value.reduce(0, +) / Double(bestBucket.value.count)
        return (clusterAverage * 100).rounded() / 100
    }

    // MARK: - Format Offset Display

    /// Formats offset as "+0.00 s" or "-1.20 s"
    static func formatOffset(_ offset: Double) -> String {
        if offset >= 0 {
            return String(format: "+%.2f s", offset)
        } else {
            return String(format: "-%.2f s", abs(offset))
        }
    }
}
