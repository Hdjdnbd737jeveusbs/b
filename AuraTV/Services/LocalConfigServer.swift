import Foundation
import Network
import SwiftData
import Observation
import Darwin

// MARK: - Form Snapshot for Mobile Setup Page

private struct SetupFormSnapshot: Sendable {
    let aioManifestURLs: String
    let tmdbKey: String
    let mdblistKey: String
    let aiProvider: String
    let aiApiKey: String
}

// MARK: - Local HTTP Config Server (Starts Only on QR Onboarding Screen)

@Observable
@MainActor
final class LocalConfigServer {
    var isRunning: Bool = false
    var setupURLString: String? = nil
    var statusMessage: String = "Starting local web server..."
    var errorMessage: String? = nil
    var savedSubmissionsCount: Int = 0
    var lastSavedSummary: String? = nil

    private var fontUploadPath = ""
    private var listener: NWListener?
    private let networkQueue = DispatchQueue(label: "com.auratv.localconfigserver", qos: .userInitiated)
    private var activeConnections: [UUID: HTTPClientConnection] = [:]
    private weak var modelContext: ModelContext?
    private var onConfigSaved: (() -> Void)?

    func start(context: ModelContext, onConfigSaved: @escaping () -> Void) {
        stop()
        fontUploadPath = "/fonts/" + UUID().uuidString
        self.modelContext = context
        self.onConfigSaved = onConfigSaved
        self.errorMessage = nil
        self.statusMessage = "Starting local web server..."

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }

            listener.newConnectionHandler = { [weak self] nwConnection in
                Task { @MainActor in
                    self?.acceptConnection(nwConnection)
                }
            }

            listener.start(queue: networkQueue)
        } catch {
            self.isRunning = false
            self.errorMessage = "Could not start local server: \(error.localizedDescription)"
            self.statusMessage = "Server unavailable"
        }
    }

    func stop() {
        for conn in activeConnections.values {
            conn.cancel()
        }
        activeConnections.removeAll()

        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil

        isRunning = false
        setupURLString = nil
        statusMessage = "Server stopped"
    }

    // MARK: - Listener Lifecycle

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue else { return }
            let ip = Self.localIPv4Address() ?? "127.0.0.1"
            let url = "http://\(ip):\(port)"
            setupURLString = url
            isRunning = true
            errorMessage = nil
            statusMessage = "Ready on \(url)"
        case .failed(let error):
            isRunning = false
            setupURLString = nil
            errorMessage = error.localizedDescription
            statusMessage = "Server error"
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func acceptConnection(_ nwConnection: NWConnection) {
        let id = UUID()
        let client = HTTPClientConnection(
            connection: nwConnection,
            queue: networkQueue,
            onRequest: { [weak self] method, path, body in
                guard let self else {
                    return (503, "text/plain; charset=utf-8", Data("Server stopped".utf8))
                }
                return await self.handleHTTPRequest(method: method, path: path, body: body)
            },
            onClose: { [weak self] in
                Task { @MainActor in
                    self?.activeConnections.removeValue(forKey: id)
                }
            }
        )
        activeConnections[id] = client
        client.start()
    }

    // MARK: - HTTP Request Handling

    private func handleHTTPRequest(method: String, path: String, body: Data) async -> (Int, String, Data) {
        if method == "POST", path == fontUploadPath {
            do {
                let name = try ImportedSubtitleFonts.install(body)
                let message = "Font installed: " + name
                lastSavedSummary = message
                return (200, "text/plain; charset=utf-8", Data(message.utf8))
            } catch {
                return (400, "text/plain; charset=utf-8", Data(error.localizedDescription.utf8))
            }
        }
        if method == "POST" && (path == "/save" || path.hasPrefix("/save?")) {
            let fields = Self.parseFormURLEncoded(body)
            let rawManifests = fields["aio_urls"] ?? ""
            let tmdbKey = (fields["tmdb_key"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let mdblistKey = (fields["mdblist_key"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let aiProvider = (fields["ai_provider"] ?? "OpenAI").trimmingCharacters(in: .whitespacesAndNewlines)
            let aiKey = (fields["ai_key"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            applySubmittedConfig(
                rawManifests: rawManifests,
                tmdbKey: tmdbKey,
                mdblistKey: mdblistKey,
                aiProvider: aiProvider,
                aiKey: aiKey
            )

            let html = Self.savedConfirmationHTML(snapshot: currentSnapshot())
            return (200, "text/html; charset=utf-8", Data(html.utf8))
        }

        let html = Self.onboardingFormHTML(snapshot: currentSnapshot(), fontUploadPath: fontUploadPath)
        return (200, "text/html; charset=utf-8", Data(html.utf8))
    }

    private func currentSnapshot() -> SetupFormSnapshot {
        guard let context = modelContext,
              let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first else {
            return SetupFormSnapshot(
                aioManifestURLs: AIOStreamsService.shared.combinedManifestInput,
                tmdbKey: TMDBService.shared.apiKey,
                mdblistKey: MDBListService.shared.apiKey,
                aiProvider: "OpenAI",
                aiApiKey: ""
            )
        }

        let combinedManifests: String
        if settings.aioStreamsAdditionalUrls.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            combinedManifests = settings.aioStreamsUrl
        } else if settings.aioStreamsUrl.isEmpty {
            combinedManifests = settings.aioStreamsAdditionalUrls
        } else {
            combinedManifests = "\(settings.aioStreamsUrl)\n\(settings.aioStreamsAdditionalUrls)"
        }

        return SetupFormSnapshot(
            aioManifestURLs: combinedManifests,
            tmdbKey: settings.tmdbApiKey,
            mdblistKey: settings.mdblistApiKey,
            aiProvider: settings.aiTranslationProvider,
            aiApiKey: settings.aiTranslationApiKey
        )
    }

    private func applySubmittedConfig(
        rawManifests: String,
        tmdbKey: String,
        mdblistKey: String,
        aiProvider: String,
        aiKey: String
    ) {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<AppSettings>(
            predicate: #Predicate<AppSettings> { $0.id == "default" }
        )
        let settings: AppSettings
        if let existing = try? context.fetch(descriptor).first {
            settings = existing
        } else {
            settings = AppSettings()
            context.insert(settings)
        }

        let manifestLines = rawManifests
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
            .map { AIOStreamsService.normalizedManifestURL(from: $0) }
            .filter { !$0.isEmpty }

        settings.aioStreamsUrl = manifestLines.first ?? ""
        settings.aioStreamsAdditionalUrls = manifestLines.dropFirst().joined(separator: "\n")
        if !tmdbKey.isEmpty {
            settings.tmdbApiKey = tmdbKey
        }
        settings.mdblistApiKey = mdblistKey
        if SettingsViewModel.aiTranslationProviderOptions.contains(aiProvider) {
            settings.aiTranslationProvider = aiProvider
        }
        settings.aiTranslationApiKey = aiKey
        if !aiKey.isEmpty {
            settings.aiTranslationEnabled = true
        }

        try? context.save()

        if !settings.tmdbApiKey.isEmpty { TMDBService.shared.apiKey = settings.tmdbApiKey }
        AIOStreamsService.shared.manifestURL = settings.aioStreamsUrl
        AIOStreamsService.shared.additionalManifestURLs = settings.aioStreamsAdditionalUrls
        MDBListService.shared.apiKey = settings.mdblistApiKey

        savedSubmissionsCount += 1
        var updatedParts: [String] = []
        if !manifestLines.isEmpty { updatedParts.append("\(manifestLines.count) manifest URL(s)") }
        if !tmdbKey.isEmpty { updatedParts.append("TMDB") }
        if !mdblistKey.isEmpty { updatedParts.append("MDBList") }
        if !aiKey.isEmpty { updatedParts.append("AI Translation (\(settings.aiTranslationProvider))") }
        lastSavedSummary = updatedParts.isEmpty ? "Saved settings from phone" : "Saved: \(updatedParts.joined(separator: ", "))"

        onConfigSaved?()
    }

    // MARK: - Form Parsing & LAN IP Helpers

    private static func parseFormURLEncoded(_ data: Data) -> [String: String] {
        guard let bodyString = String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for pair in bodyString.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = parts.first else { continue }
            let rawVal = parts.count > 1 ? String(parts[1]) : ""
            let key = String(rawKey).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(rawKey)
            let val = rawVal.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? rawVal
            result[key] = val
        }
        return result
    }

    private static func localIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var preferredEn0: String?
        var preferredEn1: String?
        var fallbackPrivate: String?
        var fallbackAny: String?

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp && !isLoopback, let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostname)
                    let ifName = String(cString: interface.ifa_name)
                    if ifName == "en0" && !ip.hasPrefix("169.254.") {
                        preferredEn0 = ip
                    } else if ifName == "en1" && !ip.hasPrefix("169.254.") {
                        preferredEn1 = ip
                    } else if !ip.hasPrefix("169.254.") && fallbackPrivate == nil {
                        fallbackPrivate = ip
                    } else if fallbackAny == nil {
                        fallbackAny = ip
                    }
                }
            }
            ptr = interface.ifa_next
        }

        return preferredEn0 ?? preferredEn1 ?? fallbackPrivate ?? fallbackAny
    }

    // MARK: - Responsive Mobile HTML Templates

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func onboardingFormHTML(snapshot: SetupFormSnapshot, fontUploadPath: String) -> String {
        let providers = SettingsViewModel.aiTranslationProviderOptions.map { provider in
            let selected = provider == snapshot.aiProvider ? " selected" : ""
            return "<option value=\"\(escapeHTML(provider))\"\(selected)>\(escapeHTML(provider))</option>"
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
          <title>AuraTV Quick Setup</title>
          <style>
            :root { color-scheme: dark; }
            body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; background: #090b10; color: #f4f6fb; padding: 24px 16px 40px; }
            .card { max-width: 560px; margin: 0 auto; background: #141822; border: 1px solid rgba(255,255,255,0.1); border-radius: 20px; padding: 24px; box-shadow: 0 24px 60px rgba(0,0,0,0.55); }
            h1 { margin: 0 0 6px; font-size: 24px; font-weight: 700; }
            p.sub { margin: 0 0 22px; color: #9aa3b2; font-size: 14px; line-height: 1.45; }
            label { display: block; font-size: 13px; font-weight: 600; color: #dce2ee; margin: 16px 0 6px; }
            input, textarea, select { width: 100%; box-sizing: border-box; background: #0c0f16; color: #fff; border: 1px solid rgba(255,255,255,0.16); border-radius: 12px; padding: 12px 14px; font-size: 15px; font-family: inherit; }
            textarea { min-height: 88px; resize: vertical; }
            .hint { font-size: 12px; color: #7f8899; margin-top: 5px; }
            button { margin-top: 24px; width: 100%; border: 0; border-radius: 999px; background: #ffffff; color: #090b10; font-size: 16px; font-weight: 700; padding: 14px 20px; cursor: pointer; }
            button:active { opacity: 0.85; }
          </style>
        </head>
        <body>
          <div class="card">
            <h1>AuraTV Phone Setup</h1>
            <p class="sub">Paste your streaming manifest URLs and API keys below, then tap Save to send them straight to your Apple TV.</p>
            <form method="POST" action="/save">
              <label for="aio_urls">Stremio / AIOStreams / Nuvio Manifest URL(s)</label>
              <textarea id="aio_urls" name="aio_urls" placeholder="https://aiostreams.example.com/manifest.json&#10;(One manifest URL per line)">\(escapeHTML(snapshot.aioManifestURLs))</textarea>
              <div class="hint">Enter one URL, or paste multiple manifest URLs separated by new lines.</div>

              <label for="tmdb_key">TMDB API Key (v3)</label>
              <input id="tmdb_key" name="tmdb_key" type="text" autocomplete="off" value="\(escapeHTML(snapshot.tmdbKey))" placeholder="Optional custom TMDB v3 key" />

              <label for="mdblist_key">MDBList API Key</label>
              <input id="mdblist_key" name="mdblist_key" type="text" autocomplete="off" value="\(escapeHTML(snapshot.mdblistKey))" placeholder="Enter MDBList API key for multi-source ratings" />

              <label for="ai_provider">AI Subtitle Translation Provider</label>
              <select id="ai_provider" name="ai_provider">
                \(providers)
              </select>

              <label for="ai_key">AI Translation API Key</label>
              <input id="ai_key" name="ai_key" type="password" autocomplete="off" value="\(escapeHTML(snapshot.aiApiKey))" placeholder="OpenAI / Gemini / Claude / Groq key" />

              <button type="submit">Save to Apple TV</button>
            </form>
            <section>
              <h2>Custom subtitle fonts</h2>
              <label for="font-file">Choose a TTF or OTF file (up to 6 MB)</label>
              <input type="file" id="font-file" accept=".ttf,.otf">
              <p id="font-result" role="status"></p>
            </section>
            <script>
              document.getElementById('font-file').onchange = async function () {
                const file = this.files[0];
                if (!file) return;
                const result = document.getElementById('font-result');
                if (file.size > 6 * 1024 * 1024) { result.textContent = 'File exceeds 6 MB.'; return; }
                result.textContent = 'Uploading…';
                try {
                  const response = await fetch('\(fontUploadPath)', { method: 'POST', body: file });
                  result.textContent = await response.text();
                } catch {
                  result.textContent = 'Upload failed. Check that Apple TV setup is still open.';
                }
              };
            </script>
          </div>
        </body>
        </html>
        """
    }

    private static func savedConfirmationHTML(snapshot: SetupFormSnapshot) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
          <title>Saved to AuraTV</title>
          <style>
            body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #090b10; color: #f4f6fb; padding: 32px 16px; }
            .card { max-width: 520px; margin: 0 auto; background: #141822; border: 1px solid rgba(52,199,89,0.45); border-radius: 20px; padding: 28px; text-align: center; }
            .badge { display: inline-block; background: rgba(52,199,89,0.18); color: #67e883; padding: 8px 14px; border-radius: 999px; font-weight: 700; font-size: 14px; margin-bottom: 14px; }
            h1 { margin: 0 0 8px; font-size: 24px; }
            p { color: #9aa3b2; font-size: 15px; line-height: 1.5; }
            a { display: inline-block; margin-top: 20px; background: #fff; color: #090b10; text-decoration: none; font-weight: 700; padding: 12px 24px; border-radius: 999px; }
          </style>
        </head>
        <body>
          <div class="card">
            <div class="badge">✓ Sent to Apple TV</div>
            <h1>Configuration Saved</h1>
            <p>Your AuraTV settings have been updated and saved cleanly. You can close this page now or edit fields again.</p>
            <a href="/">Edit Again</a>
          </div>
        </body>
        </html>
        """
    }
}

// MARK: - Buffered HTTP Connection Helper

private final class HTTPClientConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let onRequest: @Sendable (String, String, Data) async -> (Int, String, Data)
    private let onClose: @Sendable () -> Void

    private var buffer = Data()
    private var didHandleRequest = false

    init(
        connection: NWConnection,
        queue: DispatchQueue,
        onRequest: @escaping @Sendable (String, String, Data) async -> (Int, String, Data),
        onClose: @escaping @Sendable () -> Void
    ) {
        self.connection = connection
        self.queue = queue
        self.onRequest = onRequest
        self.onClose = onClose
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.close()
            } else if case .cancelled = state {
                self?.onClose()
            }
        }
        connection.start(queue: queue)
        receiveNextChunk()
    }

    func cancel() {
        connection.cancel()
    }

    private func close() {
        connection.cancel()
        onClose()
    }

    private func receiveNextChunk() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            if let content, !content.isEmpty {
                guard self.buffer.count + content.count <= ImportedSubtitleFonts.maximumBytes + 16384 else {
                    self.sendResponse(status: 413, contentType: "text/plain", body: Data("File too large".utf8))
                    return
                }
                self.buffer.append(content)
            }
            if error != nil {
                self.close()
                return
            }
            if !self.didHandleRequest, let parsed = self.tryParseCompleteRequest(isEOF: isComplete) {
                self.didHandleRequest = true
                Task {
                    let (status, contentType, responseBody) = await self.onRequest(parsed.method, parsed.path, parsed.body)
                    self.sendResponse(status: status, contentType: contentType, body: responseBody)
                }
                return
            }
            if isComplete {
                self.close()
            } else {
                self.receiveNextChunk()
            }
        }
    }

    private func tryParseCompleteRequest(isEOF: Bool) -> (method: String, path: String, body: Data)? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEndRange = buffer.range(of: separator) else { return nil }
        let headerData = buffer.subdata(in: buffer.startIndex..<headerEndRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0]).uppercased()
        let path = String(parts[1])

        var contentLength = 0
        for line in lines.dropFirst() {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:"),
               let val = Int(lower.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) {
                contentLength = val
            }
        }

        guard (0...ImportedSubtitleFonts.maximumBytes).contains(contentLength) else { return nil }
        let bodyStart = headerEndRange.upperBound
        let availableBody = buffer.count - bodyStart
        if availableBody < contentLength && !isEOF {
            return nil
        }

        let bodyEnd = min(buffer.count, bodyStart + max(0, contentLength))
        let body = bodyStart < bodyEnd ? buffer.subdata(in: bodyStart..<bodyEnd) : Data()
        return (method, path, body)
    }

    private func sendResponse(status: Int, contentType: String, body: Data) {
        let statusText = status == 200 ? "OK" : "Error"
        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        var fullData = Data(header.utf8)
        fullData.append(body)

        connection.send(content: fullData, completion: .contentProcessed { [weak self] _ in
            self?.close()
        })
    }
}
