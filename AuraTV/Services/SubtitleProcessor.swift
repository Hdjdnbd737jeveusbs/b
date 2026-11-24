import Foundation
import SwiftUI

// MARK: - Subtitle Processor (Arabic RTL & Punctuation Fixes)

final class SubtitleProcessor {

    // MARK: Unicode Directional Constants
    static let RLM: Character = "\u{200F}" // Right-to-Left Mark
    static let LRM: Character = "\u{200E}" // Left-to-Right Mark
    static let RLE: Character = "\u{202B}" // Right-to-Left Embedding
    static let PDF: Character = "\u{202C}" // Pop Directional Formatting
    static let ALM: Character = "\u{061C}" // Arabic Letter Mark

    // MARK: - Process Cue Text

    /// Process cue text according to sync settings (Arabic RTL fixes, punctuation reordering)
    static func process(
        text: String,
        isArabic: Bool,
        fixRTL: Bool = true,
        fixReversedPunctuation: Bool = true
    ) -> String {
        guard isArabic else { return text }

        let lines = text.components(separatedBy: "\n")
        let processedLines = lines.map { line in
            processLine(
                line: line,
                fixRTL: fixRTL,
                fixReversedPunctuation: fixReversedPunctuation
            )
        }

        return processedLines.joined(separator: "\n")
    }

    // MARK: - Process Single Line

    private static func processLine(
        line: String,
        fixRTL: Bool,
        fixReversedPunctuation: Bool
    ) -> String {
        var str = line.trimmingCharacters(in: .whitespaces)
        guard !str.isEmpty else { return "" }

        // 1. Fix reversed punctuation (e.g. dialogue dash, question marks, exclamation)
        if fixReversedPunctuation {
            str = fixPunctuationForArabic(str)
        }

        // 2. Fix RTL wrapping & embedding
        if fixRTL {
            // Prepend RLE + ALM and terminate with PDF + RLM
            // This forces Apple TV SwiftUI Text engine to render in strictly RTL flow
            str = "\(RLE)\(ALM)\(str)\(PDF)\(RLM)"
        }

        return str
    }

    // MARK: - Punctuation Fixes

    private static func fixPunctuationForArabic(_ line: String) -> String {
        var text = line

        // Replace Western question mark with Arabic question mark if the line has Arabic letters
        if text.contains("?") && containsArabicCharacters(text) {
            text = text.replacingOccurrences(of: "?", with: "؟")
        }

        // Replace Western comma with Arabic comma when adjacent to Arabic words
        if text.contains(",") && containsArabicCharacters(text) {
            text = text.replacingOccurrences(of: ",", with: "،")
        }

        // Fix dialogue dash: in LTR, a leading dash "- " on an Arabic line jumps to the right end
        // We prepend RLM before the dash to anchor it to the Arabic start
        if text.hasPrefix("- ") || text.hasPrefix("-\u{00A0}") {
            let rest = String(text.dropFirst(2))
            text = "\(RLM)-\u{00A0}\(rest)"
        } else if text.hasPrefix("-") {
            let rest = String(text.dropFirst(1))
            text = "\(RLM)-\u{00A0}\(rest)"
        }

        // Fix trailing punctuation (periods, question marks, exclamation) jumping to the left
        // If a line ends with punctuation like ".", "!", "؟", "...", appending an RLM prevents it from flipping
        let trailingPunctuationSet: Set<Character> = [".", "!", "؟", "?", ":", "…", ")", "]", "»"]
        if let lastChar = text.last, trailingPunctuationSet.contains(lastChar) {
            text = "\(text)\(RLM)"
        }

        // Fix leading punctuation typed backwards: e.g. "!أهلاً" -> "أهلاً!"
        let leadingPunctuationSet: Set<Character> = ["!", "؟", "?", ".", ":", "…"]
        if let firstChar = text.first, leadingPunctuationSet.contains(firstChar) {
            text.removeFirst()
            text = "\(text)\(firstChar)\(RLM)"
        }

        // Swap mirrored brackets when needed
        text = fixMirroredBrackets(text)

        return text
    }

    /// Swap parentheses and brackets if they appear inverted in Arabic context
    private static func fixMirroredBrackets(_ text: String) -> String {
        // Only swap if both or one bracket is used in an Arabic line
        var result = ""
        for char in text {
            switch char {
            case "(":
                result.append(")")
            case ")":
                result.append("(")
            case "[":
                result.append("]")
            case "]":
                result.append("[")
            case "{":
                result.append("}")
            case "}":
                result.append("{")
            default:
                result.append(char)
            }
        }
        return result
    }

    // MARK: - Arabic Characters Check

    static func containsArabicCharacters(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if (0x0600...0x06FF).contains(scalar.value) ||
               (0x0750...0x077F).contains(scalar.value) ||
               (0x08A0...0x08FF).contains(scalar.value) ||
               (0xFB50...0xFDFF).contains(scalar.value) ||
               (0xFE70...0xFEFF).contains(scalar.value) {
                return true
            }
        }
        return false
    }

    // MARK: - Supported Arabic & System Fonts (Native tvOS 18+ Fonts)

    static let availableFonts: [String] = [
        "System",
        "GeezaPro",
        "Damascus",
        "AlBayan",
        "Baghdad",
        "DecoTypeNaskh",
        "Farah",
        "KufiStandardGK"
    ]
}
