import Foundation
import Testing
@testable import AgentSpeed

@Suite("Merged Sub4Tokens balances")
@MainActor
struct SubscriptionBalanceTests {
    private func status(_ id: String, currency: String = "USD", remaining: Double? = 10) -> SubscriptionBalanceStatus {
        SubscriptionBalanceStatus(provider: id, name: id.uppercased(), enabled: true, configured: true, currency: currency,
            siteURL: "https://example.invalid", errorCode: nil, errorMessage: nil, totalLimitUSD: 100,
            usedUSD: 2, remainingUSD: remaining, refreshedAt: nil)
    }
    @Test func migrationPreservesOptionsAndCurrenciesWithoutReadingOrCopyingSecrets() throws {
        let name = "Balances.\(UUID().uuidString)"
        let current = try #require(UserDefaults(suiteName: name))
        let legacy = try #require(UserDefaults(suiteName: name + ".old"))
        defer { current.removePersistentDomain(forName: name); legacy.removePersistentDomain(forName: name + ".old") }
        legacy.set("https://example.invalid", forKey: "sub2_base_url")
        legacy.set(["a", "b", "c"], forKey: "selected_providers")
        legacy.set(true, forKey: "selection_configured")
        legacy.set("total", forKey: "display_mode")
        legacy.set(180, forKey: "refresh_seconds")
        legacy.set(8, forKey: "rotation_seconds")
        let state = SubscriptionBalanceState(defaults: current, legacy: legacy)
        #expect(state.baseURL == "https://example.invalid" && state.displayMode == .total)
        #expect(state.refreshSeconds == 180 && state.rotationSeconds == 8)
        #expect(state.adminAPIKey.isEmpty && state.accessToken.isEmpty && state.refreshToken.isEmpty)
        state.statuses = [status("a"), status("b", remaining: 20), status("c", currency: "CNY", remaining: 50)]
        #expect(state.currencyTotals.count == 2)
        #expect(state.currencyTotals.first { $0.currency == "USD" }?.amount == 30)
        #expect(state.currencyTotals.first { $0.currency == "CNY" }?.amount == 50)
        state.displayMode = .rotation
        state.rotationIndex = 1
        #expect(state.menuBarTitle.hasPrefix("B "))
        state.selectedProviderIDs = []
        #expect(state.menuBarTitle == "Sub 4 Tokens")
        legacy.set("selected", forKey: "display_mode")
        let again = SubscriptionBalanceState(defaults: current, legacy: legacy)
        #expect(again.displayMode == .rotation && again.selectedProviderIDs.isEmpty)
    }

    @Test func rotationSkipsUnavailableBalancesAndShowsUpstreamCurrency() throws {
        let name = "Balances.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = SubscriptionBalanceState(defaults: defaults, legacy: nil)
        state.statuses = [status("missing", remaining: nil), status("a"), status("b", currency: "EUR", remaining: 20)]
        state.selectedProviderIDs = ["missing", "a", "b"]
        #expect(state.visibleStatuses.count == 2)
        state.rotationIndex = 1
        #expect(state.currentStatus?.provider == "b")
        #expect(state.menuBarTitle.contains("€20"))
        state.showsMenuBar = false
        #expect(SubscriptionBalanceState(defaults: defaults, legacy: nil).showsMenuBar == false)
    }
}
