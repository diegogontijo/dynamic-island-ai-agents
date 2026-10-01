import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var claude = ProviderSnapshot.empty
    @Published private(set) var codex = ProviderSnapshot.empty
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?

    private let claudeProvider = ClaudeProvider()
    private let codexProvider = CodexProvider()
    private var timer: Timer?

    /// The Claude usage endpoint is rate limited, so poll gently in the background.
    private let pollInterval: TimeInterval = 180
    private let staleAfter: TimeInterval = 30

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Called when the panel opens: refresh unless the data is very recent,
    /// or a window has already passed its reset time.
    func refreshIfStale() {
        let now = Date()
        let resetPassed = [claude.usage?.session?.resetsAt, codex.usage?.session?.resetsAt]
            .compactMap { $0 }
            .contains { $0 < now }
        if resetPassed || lastRefresh.map({ now.timeIntervalSince($0) > staleAfter }) ?? true {
            refresh()
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            async let claudeResult = Self.capture { try await self.claudeProvider.fetch() }
            async let codexResult = Self.capture { try await self.codexProvider.fetch() }
            let (c, x) = await (claudeResult, codexResult)
            claude = Self.merge(claude, with: c)
            codex = Self.merge(codex, with: x)
            lastRefresh = Date()
            isRefreshing = false
        }
    }

    private nonisolated static func capture(_ work: @Sendable () async throws -> Usage) async -> Result<Usage, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    /// On failure keep the last good numbers and just attach the error message.
    private static func merge(_ old: ProviderSnapshot, with result: Result<Usage, Error>) -> ProviderSnapshot {
        switch result {
        case .success(let usage):
            return ProviderSnapshot(usage: usage, error: nil, updatedAt: Date())
        case .failure(let error):
            let message = (error as? LocalizedError)?.errorDescription ?? "Sem conexão"
            return ProviderSnapshot(usage: old.usage, error: message, updatedAt: old.updatedAt)
        }
    }
}
