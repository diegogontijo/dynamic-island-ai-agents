import Foundation

/// Reads the OAuth token Claude Code keeps in the login Keychain and queries the
/// same usage endpoint that `/usage` uses. The token is never refreshed here, so
/// Claude Code's own credentials are left untouched.
struct ClaudeProvider {
    private struct Credentials: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let expiresAt: Double?
        }
        let claudeAiOauth: OAuth?
    }

    private struct Response: Decodable {
        struct Window: Decodable {
            let utilization: Double?
            let resets_at: String?
        }
        let five_hour: Window?
        let seven_day: Window?
    }

    func fetch() async throws -> Usage {
        let token = try await Self.readToken()

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTP.check(response, tool: "Claude Code")

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        func window(_ w: Response.Window?) -> UsageWindow? {
            guard let w else { return nil }
            return UsageWindow(usedPercent: w.utilization ?? 0, resetsAt: DateParsing.iso8601(w.resets_at))
        }
        return Usage(session: window(decoded.five_hour), weekly: window(decoded.seven_day))
    }

    private static func readToken() async throws -> String {
        let output = try await Shell.run("/usr/bin/security",
                                         ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
        guard let output, let data = output.data(using: .utf8),
              let creds = try? JSONDecoder().decode(Credentials.self, from: data),
              let oauth = creds.claudeAiOauth else {
            throw UsageError.notLoggedIn("Claude Code")
        }
        if let expiresAt = oauth.expiresAt, Date(timeIntervalSince1970: expiresAt / 1000) < Date() {
            throw UsageError.expired("Claude Code")
        }
        return oauth.accessToken
    }
}

/// Reads the ChatGPT login stored by the Codex CLI in ~/.codex/auth.json and
/// queries the endpoint behind Codex's `/status` rate-limit display.
struct CodexProvider {
    private struct Auth: Decodable {
        struct Tokens: Decodable {
            let access_token: String
            let account_id: String?
        }
        let tokens: Tokens?
    }

    private struct Response: Decodable {
        struct Window: Decodable {
            let used_percent: Double
            let limit_window_seconds: Int?
            let reset_at: Double?
        }
        struct RateLimit: Decodable {
            let primary_window: Window?
            let secondary_window: Window?
        }
        let rate_limit: RateLimit?
    }

    func fetch() async throws -> Usage {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        guard let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")),
              let tokens = try? JSONDecoder().decode(Auth.self, from: data).tokens else {
            throw UsageError.notLoggedIn("Codex")
        }

        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(tokens.access_token)", forHTTPHeaderField: "Authorization")
        if let account = tokens.account_id {
            request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (body, response) = try await URLSession.shared.data(for: request)
        try HTTP.check(response, tool: "Codex")

        let decoded = try JSONDecoder().decode(Response.self, from: body)
        let windows = [decoded.rate_limit?.primary_window, decoded.rate_limit?.secondary_window].compactMap { $0 }
        func window(_ w: Response.Window?) -> UsageWindow? {
            guard let w else { return nil }
            return UsageWindow(usedPercent: w.used_percent,
                               resetsAt: w.reset_at.map { Date(timeIntervalSince1970: $0) })
        }
        let session = windows.first { $0.limit_window_seconds == 5 * 3600 } ?? decoded.rate_limit?.primary_window
        let weekly = windows.first { $0.limit_window_seconds == 7 * 24 * 3600 } ?? decoded.rate_limit?.secondary_window
        return Usage(session: window(session), weekly: window(weekly))
    }
}

enum HTTP {
    static func check(_ response: URLResponse, tool: String) throws {
        guard let http = response as? HTTPURLResponse else { throw UsageError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw UsageError.expired(tool)
        case 429: throw UsageError.rateLimited
        default: throw UsageError.http(http.statusCode)
        }
    }
}

enum Shell {
    /// Runs a command and returns its trimmed stdout, or nil when it exits non-zero.
    static func run(_ path: String, _ arguments: [String]) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else { return continuation.resume(returning: nil) }
                    let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
