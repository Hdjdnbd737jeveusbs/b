import Foundation

// MARK: - AI Translation Configuration

struct SubtitleTranslationConfig: Equatable, Sendable {
    let enabled: Bool
    let provider: String
    let apiKey: String
    let targetLanguageCode: String
    let targetLanguageName: String
    let customEndpoint: String
    let modelOverride: String

    static let disabled = SubtitleTranslationConfig(
        enabled: false,
        provider: "OpenAI",
        apiKey: "",
        targetLanguageCode: "ar",
        targetLanguageName: "Arabic",
        customEndpoint: "http://localhost:11434/v1/chat/completions",
        modelOverride: ""
    )

    var isCustomProvider: Bool {
        provider == "Custom (Ollama / OpenAI)"
    }

    var resolvedEndpoint: String {
        let trimmed = customEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "http://localhost:11434/v1/chat/completions" : trimmed
    }

    var resolvedModel: String {
        let override = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty { return override }
        switch provider {
        case "Gemini": return "gemini-2.0-flash"
        case "Claude": return "claude-3-5-haiku-latest"
        case "Groq": return "llama-3.3-70b-versatile"
        case "Custom (Ollama / OpenAI)": return "llama3.2"
        default: return "gpt-4o-mini"
        }
    }

    var isConfigured: Bool {
        guard enabled else { return false }
        if isCustomProvider {
            return URL(string: resolvedEndpoint) != nil
        }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var cacheNamespace: String {
        "\(provider)|\(resolvedModel)|\(targetLanguageCode)"
    }
}

// MARK: - AI Subtitle Translation Service (BYOK)

actor AITranslationService {
    static let shared = AITranslationService()

    private let session: URLSession
    private var cueCache: [String: [Int: String]] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 35
        self.session = URLSession(configuration: config)
    }

    /// Translates a batch of upcoming subtitle cues and caches them in memory.
    func translateBatch(
        cues: [AuraSubtitleCue],
        trackKey: String,
        config: SubtitleTranslationConfig
    ) async -> [Int: String] {
        guard config.isConfigured, !cues.isEmpty else { return [:] }

        let namespaceKey = "\(trackKey)|\(config.cacheNamespace)"
        let existing = cueCache[namespaceKey] ?? [:]

        var resolved: [Int: String] = [:]
        var missing: [AuraSubtitleCue] = []
        missing.reserveCapacity(cues.count)

        for cue in cues {
            if let cached = existing[cue.id] {
                resolved[cue.id] = cached
            } else if !cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missing.append(cue)
            }
        }

        guard !missing.isEmpty else { return resolved }

        do {
            let fresh = try await performProviderRequest(cues: missing, config: config)
            var merged = cueCache[namespaceKey] ?? [:]
            for (id, translated) in fresh where !translated.isEmpty {
                merged[id] = translated
                resolved[id] = translated
            }
            cueCache[namespaceKey] = merged
        } catch {
            // Gracefully leave uncached cues in their original language when network/key fails.
        }

        return resolved
    }

    func cachedTranslations(for trackKey: String, config: SubtitleTranslationConfig) -> [Int: String] {
        cueCache["\(trackKey)|\(config.cacheNamespace)"] ?? [:]
    }

    func clearCache() {
        cueCache.removeAll()
    }

    // MARK: - Provider Dispatch

    private func performProviderRequest(
        cues: [AuraSubtitleCue],
        config: SubtitleTranslationConfig
    ) async throws -> [Int: String] {
        var inputMap: [String: String] = [:]
        inputMap.reserveCapacity(cues.count)
        for cue in cues {
            inputMap[String(cue.id)] = cue.text
        }

        let inputData = try JSONSerialization.data(withJSONObject: inputMap, options: [.sortedKeys])
        let inputJSON = String(data: inputData, encoding: .utf8) ?? "{}"

        let systemPrompt = """
        You are a subtitle translator for movies and TV shows.
        Translate every subtitle line value in the input JSON object into \(config.targetLanguageName) (ISO 639-1 code: \(config.targetLanguageCode)).
        Rules:
        - Keep the EXACT same numeric string keys.
        - Translate naturally and concisely for on-screen TV subtitles.
        - Preserve line breaks (\\n) and speaker dialogue dashes (- ).
        - Return ONLY a valid JSON object mapping each key to its translated string.
        """

        let rawText: String
        switch config.provider {
        case "Gemini":
            rawText = try await callGemini(systemPrompt: systemPrompt, userPrompt: inputJSON, config: config)
        case "Claude":
            rawText = try await callClaude(systemPrompt: systemPrompt, userPrompt: inputJSON, config: config)
        case "Groq":
            rawText = try await callOpenAICompatible(
                endpoint: "https://api.groq.com/openai/v1/chat/completions",
                systemPrompt: systemPrompt,
                userPrompt: inputJSON,
                config: config
            )
        case "Custom (Ollama / OpenAI)":
            rawText = try await callOpenAICompatible(
                endpoint: config.resolvedEndpoint,
                systemPrompt: systemPrompt,
                userPrompt: inputJSON,
                config: config
            )
        default:
            rawText = try await callOpenAICompatible(
                endpoint: "https://api.openai.com/v1/chat/completions",
                systemPrompt: systemPrompt,
                userPrompt: inputJSON,
                config: config
            )
        }

        return parseTranslatedJSON(rawText)
    }

    private func callOpenAICompatible(
        endpoint: String,
        systemPrompt: String,
        userPrompt: String,
        config: SubtitleTranslationConfig
    ) async throws -> String {
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let payload: [String: Any] = [
            "model": config.resolvedModel,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = root?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let content = message?["content"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return content
    }

    private func callGemini(
        systemPrompt: String,
        userPrompt: String,
        config: SubtitleTranslationConfig
    ) async throws -> String {
        let model = config.resolvedModel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "gemini-2.0-flash"
        let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)") else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": userPrompt]]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = root?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        guard let text = parts?.first?["text"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return text
    }

    private func callClaude(
        systemPrompt: String,
        userPrompt: String,
        config: SubtitleTranslationConfig
    ) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let payload: [String: Any] = [
            "model": config.resolvedModel,
            "max_tokens": 2048,
            "temperature": 0.2,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let blocks = root?["content"] as? [[String: Any]]
        guard let text = blocks?.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return text
    }

    // MARK: - Response Parsing

    private func parseTranslatedJSON(_ rawText: String) -> [Int: String] {
        let cleaned = extractJSONObjectString(from: rawText)
        guard let data = cleaned.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        var output: [Int: String] = [:]
        output.reserveCapacity(dict.count)
        for (key, value) in dict {
            if let id = Int(key.trimmingCharacters(in: .whitespacesAndNewlines)),
               let text = value as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    output[id] = trimmed
                }
            }
        }
        return output
    }

    private func extractJSONObjectString(from text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            if let firstNewline = trimmed.firstIndex(of: "\n") {
                trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
            }
            if let lastFence = trimmed.range(of: "```", options: .backwards) {
                trimmed = String(trimmed[..<lastFence.lowerBound])
            }
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }
        return trimmed
    }
}
