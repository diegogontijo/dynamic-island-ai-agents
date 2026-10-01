import Foundation

struct UsageWindow: Equatable {
    /// Percentage of the window already consumed (0–100).
    var usedPercent: Double
    var resetsAt: Date?

    var remainingPercent: Double { min(100, max(0, 100 - usedPercent)) }
}

struct Usage: Equatable {
    var session: UsageWindow?
    var weekly: UsageWindow?
}

struct ProviderSnapshot: Equatable {
    var usage: Usage?
    var error: String?
    var updatedAt: Date?

    static let empty = ProviderSnapshot()
}

enum UsageError: LocalizedError {
    case notLoggedIn(String)
    case expired(String)
    case rateLimited
    case http(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notLoggedIn(let tool): return "Faça login no \(tool)"
        case .expired(let tool): return "Login expirado — abra o \(tool) para renovar"
        case .rateLimited: return "Muitas consultas, tentando de novo em breve"
        case .http(let code): return "Erro do servidor (\(code))"
        case .invalidResponse: return "Resposta inesperada do servidor"
        }
    }
}

enum DateParsing {
    static func iso8601(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        // The API returns microseconds, which ISO8601DateFormatter does not always accept.
        let trimmed = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }
}
