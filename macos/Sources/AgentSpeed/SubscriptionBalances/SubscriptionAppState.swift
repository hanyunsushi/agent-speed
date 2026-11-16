import Foundation
import Observation

@MainActor
@Observable
final class SubscriptionBalanceState {
    private enum Keys {
        static let baseURL = "sub2_base_url"
        static let selected = "selected_providers"
        static let mode = "display_mode"
        static let refresh = "refresh_seconds"
        static let rotation = "rotation_seconds"
        static let selectionConfigured = "selection_configured"
    }

    var baseURL: String { didSet {
        defaults.set(baseURL, forKey: Keys.baseURL)
        if baseURL != oldValue { statuses = []; lastRefresh = nil }
    } }
    var adminAPIKey = ""
    var accessToken = ""
    var refreshToken = ""
    var statuses: [SubscriptionBalanceStatus] = []
    var selectedProviderIDs: Set<String> {
        didSet {
            defaults.set(Array(selectedProviderIDs), forKey: Keys.selected)
            hasExplicitSelection = true
            defaults.set(true, forKey: Keys.selectionConfigured)
        }
    }
    var displayMode: SubscriptionBalanceMode { didSet { defaults.set(displayMode.rawValue, forKey: Keys.mode) } }
    var refreshSeconds: Double { didSet { defaults.set(refreshSeconds, forKey: Keys.refresh) } }
    var rotationSeconds: Double { didSet { defaults.set(rotationSeconds, forKey: Keys.rotation) } }
    var rotationIndex = 0
    var lastRefresh: Date?
    var isRefreshing = false
    var errorMessage: String?

    private let defaults: UserDefaults
    private let client: SubscriptionAPIClient
    private let saveTokens: (String, String) throws -> Void
    private var refreshTask: Task<Void, Never>?
    private var rotationTask: Task<Void, Never>?
    private var hasExplicitSelection = false
    private var started = false

    var showsMenuBar: Bool { didSet { defaults.set(showsMenuBar, forKey: "subscriptionBalances.showsMenuBar") } }
    var credentialError: String?

    init(defaults: UserDefaults = .standard, legacy: UserDefaults? = UserDefaults(suiteName: "com.hinaw.customize-sub-4-tokens"),
         client: SubscriptionAPIClient = SubscriptionAPIClient(),
         saveTokens: @escaping (String, String) throws -> Void = { access, refresh in
             try SubscriptionKeychain.saveToken(access)
             try SubscriptionKeychain.saveRefreshToken(refresh)
         }) {
        self.client = client
        self.saveTokens = saveTokens
        self.defaults = defaults
        if !defaults.bool(forKey: "subscriptionBalances.migrated") {
            for key in [Keys.baseURL, Keys.selected, Keys.mode, Keys.refresh, Keys.rotation, Keys.selectionConfigured] {
                if defaults.object(forKey: key) == nil, let value = legacy?.object(forKey: key) { defaults.set(value, forKey: key) }
            }
            defaults.set(true, forKey: "subscriptionBalances.migrated")
        }
        showsMenuBar = defaults.object(forKey: "subscriptionBalances.showsMenuBar") as? Bool ?? true
        baseURL = defaults.string(forKey: Keys.baseURL) ?? "https://ai.kreeper.cc"
        selectedProviderIDs = Set(defaults.stringArray(forKey: Keys.selected) ?? [])
        hasExplicitSelection = defaults.bool(forKey: Keys.selectionConfigured)
        displayMode = SubscriptionBalanceMode(rawValue: defaults.string(forKey: Keys.mode) ?? "selected") ?? .selected
        refreshSeconds = max(30, defaults.double(forKey: Keys.refresh).nonZeroOr(300))
        rotationSeconds = max(3, defaults.double(forKey: Keys.rotation).nonZeroOr(10))

    }

    var selectedStatuses: [SubscriptionBalanceStatus] {
        statuses.filter { selectedProviderIDs.contains($0.provider) }
    }

    var currencyTotals: [SubscriptionCurrencyTotal] {
        Dictionary(grouping: selectedStatuses, by: { $0.currency.uppercased() })
            .map { key, values in SubscriptionCurrencyTotal(currency: key, amount: values.compactMap(\.remainingUSD).reduce(0, +)) }
            .sorted { $0.currency < $1.currency }
    }

    var menuBarTitle: String {
        let visible = visibleStatuses
        guard !visible.isEmpty else { return "Sub 4 Tokens" }
        switch displayMode {
        case .total:
            return currencyTotals.map { SubscriptionMoneyFormatter.compact(amount: $0.amount, currency: $0.currency) }.joined(separator: " · ")
        case .selected, .rotation:
            guard let status = currentStatus else { return "Sub 4 Tokens" }
            return "\(status.name) \(SubscriptionMoneyFormatter.compact(amount: status.remainingUSD ?? 0, currency: status.currency))"
        }
    }

    var visibleStatuses: [SubscriptionBalanceStatus] { selectedStatuses.filter { $0.remainingUSD != nil } }

    var currentStatus: SubscriptionBalanceStatus? {
        let visible = visibleStatuses
        guard !visible.isEmpty else { return nil }
        return visible[min(rotationIndex, visible.count - 1)]
    }

    func start() {
        guard !started else { return }
        started = true
        adminAPIKey = SubscriptionKeychain.readAdminAPIKey()
        accessToken = SubscriptionKeychain.readToken()
        refreshToken = SubscriptionKeychain.readRefreshToken()
        scheduleRefresh()
        restartRotation()
        if statuses.isEmpty { Task { await refresh() } }
    }

    func stop() {
        refreshTask?.cancel(); rotationTask?.cancel()
        refreshTask = nil; rotationTask = nil; started = false
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.refreshSeconds))
                if Task.isCancelled { return }
                await self.refresh()
            }
        }
    }

    func restartRotation() {
        rotationTask?.cancel()
        rotationIndex = 0
        guard displayMode == .rotation else { return }
        rotationTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.rotationSeconds))
                if Task.isCancelled { return }
                self.rotationIndex = self.visibleStatuses.isEmpty ? 0 : (self.rotationIndex + 1) % self.visibleStatuses.count
            }
        }
    }

    func setToken(_ token: String) {
        accessToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        saveCredential { try SubscriptionKeychain.saveToken(accessToken) }
    }

    func setAdminAPIKey(_ key: String) {
        adminAPIKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        saveCredential { try SubscriptionKeychain.saveAdminAPIKey(adminAPIKey) }
    }

    func setRefreshToken(_ token: String) {
        refreshToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        saveCredential { try SubscriptionKeychain.saveRefreshToken(refreshToken) }
    }

    private func saveCredential(_ operation: () throws -> Void) {
        do { try operation() }
        catch { credentialError = "Cannot save credentials in Keychain (\(error.localizedDescription))" }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        guard !baseURL.isEmpty, !adminAPIKey.isEmpty || !accessToken.isEmpty || !refreshToken.isEmpty else {
            errorMessage = "Set the Sub2API URL and an Admin API Key in Settings"
            return
        }
        let requestedBaseURL = baseURL
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let next: [SubscriptionBalanceStatus]
            if !adminAPIKey.isEmpty {
                next = try await client.fetchStatuses(baseURL: baseURL, apiKey: adminAPIKey)
            } else {
                next = try await withAutomaticRefresh { token in
                    try await client.fetchStatuses(baseURL: baseURL, token: token)
                }
            }
            guard baseURL == requestedBaseURL else { return }
            statuses = next
            if !hasExplicitSelection { selectedProviderIDs = Set(next.filter(\.enabled).map(\.provider)) }
            selectedProviderIDs.formIntersection(Set(next.map(\.provider)))
            rotationIndex = min(rotationIndex, max(0, selectedStatuses.count - 1))
            lastRefresh = Date()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func withAutomaticRefresh<T>(_ operation: (String) async throws -> T) async throws -> T {
        if accessToken.isEmpty {
            try await refreshAccessToken()
        }

        do {
            return try await operation(accessToken)
        } catch SubscriptionAPIError.unauthorized {
            try await refreshAccessToken()
            return try await operation(accessToken)
        }
    }

    private func refreshAccessToken() async throws {
        guard !refreshToken.isEmpty else { throw SubscriptionAPIError.unauthorized }
        let pair = try await client.refreshAccessToken(baseURL: baseURL, refreshToken: refreshToken)
        accessToken = pair.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pair.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            refreshToken = pair.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        try saveTokens(accessToken, refreshToken)
    }
}

private extension Double {
    func nonZeroOr(_ fallback: Double) -> Double { self > 0 ? self : fallback }
}
