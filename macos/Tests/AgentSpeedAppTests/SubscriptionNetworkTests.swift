import Foundation
import Testing
@testable import AgentSpeed

private final class BalanceURLProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "balances.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests.append(request); Self.lock.unlock()
        let path = request.url!.path
        let status: Int
        let body: String
        if path.hasSuffix("/auth/refresh") {
            status = 200; body = #"{"data":{"access_token":"new-test-access","refresh_token":"new-test-refresh","expires_in":3600}}"#
        } else if request.value(forHTTPHeaderField: "Authorization") == "Bearer expired-test-access" {
            status = 401; body = "{}"
        } else {
            status = 200
            body = #"{"data":[{"provider":"a","name":"A","enabled":true,"configured":true,"currency":"EUR","site_url":"https://balances.invalid","used_usd":2,"remaining_usd":8.5}]}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    static func take() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; let out = requests; requests = []; return out }
}

@Suite("Subscription API authentication", .serialized)
@MainActor
struct SubscriptionNetworkTests {
    private func client() -> SubscriptionAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BalanceURLProtocol.self]
        return SubscriptionAPIClient(session: URLSession(configuration: configuration))
    }
    @Test func adminKeyUsesCachedEndpointAndNeverFallsBackToBearer() async throws {
        _ = BalanceURLProtocol.take()
        let statuses = try await client().fetchStatuses(baseURL: "https://balances.invalid", apiKey: "test-admin-key")
        let requests = BalanceURLProtocol.take()
        #expect(requests.count == 1 && requests[0].url?.query == nil)
        #expect(requests[0].value(forHTTPHeaderField: "x-api-key") == "test-admin-key")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(statuses.first?.currency == "EUR" && statuses.first?.remainingUSD == 8.5)
    }
    @Test func expiredLegacyTokenRotatesOnceAndRetriesWithTheNewPair() async throws {
        _ = BalanceURLProtocol.take()
        let name = "BalanceNetwork.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var saved: (String, String)?
        let state = SubscriptionBalanceState(defaults: defaults, legacy: nil, client: client(), saveTokens: { saved = ($0, $1) })
        state.baseURL = "https://balances.invalid"
        state.accessToken = "expired-test-access"; state.refreshToken = "old-test-refresh"
        await state.refresh()
        let requests = BalanceURLProtocol.take()
        #expect(requests.count == 3)
        #expect(requests[0].url?.query == "refresh=1")
        #expect(requests[1].url?.path == "/api/v1/auth/refresh")
        #expect(requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer new-test-access")
        #expect(saved?.0 == "new-test-access" && saved?.1 == "new-test-refresh")
        #expect(state.errorMessage == nil && state.lastRefresh != nil && !state.isRefreshing)
        #expect(state.selectedProviderIDs == ["a"] && state.menuBarTitle.contains("€8.5"))
    }
}
