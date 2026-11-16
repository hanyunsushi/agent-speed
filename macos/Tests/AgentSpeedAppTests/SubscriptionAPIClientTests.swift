import XCTest
@testable import AgentSpeed

final class SubscriptionAPIClientTests: XCTestCase {
    func testStatusesURLAddsAPIV1ToHost() {
        let url = SubscriptionAPIClient.statusesURL(baseURL: "https://ai.kreeper.cc")
        XCTAssertEqual(url?.path, "/api/v1/admin/external-subscriptions/statuses")
        XCTAssertNil(url?.query)
    }

    func testStatusesURLCanForceRefresh() {
        let url = SubscriptionAPIClient.statusesURL(baseURL: "https://ai.kreeper.cc", forceRefresh: true)
        XCTAssertEqual(url?.query, "refresh=1")
    }

    func testStatusesURLKeepsExistingAPIV1Prefix() {
        let url = SubscriptionAPIClient.statusesURL(baseURL: "https://ai.kreeper.cc/api/v1/")
        XCTAssertEqual(url?.path, "/api/v1/admin/external-subscriptions/statuses")
    }

    func testRefreshURLUsesAuthEndpointWithoutStatusQuery() {
        let url = SubscriptionAPIClient.refreshURL(baseURL: "https://ai.kreeper.cc/api/v1/")
        XCTAssertEqual(url?.path, "/api/v1/auth/refresh")
        XCTAssertNil(url?.query)
    }

    func testStatusesURLRejectsNonHTTPURL() {
        XCTAssertNil(SubscriptionAPIClient.statusesURL(baseURL: "file:///tmp/statuses"))
        XCTAssertNil(SubscriptionAPIClient.statusesURL(baseURL: "not a url"))
    }

    func testDecodesSub2APIEnvelopeAndKeepsUpstreamCurrency() throws {
        let body = Data("""
        {"code":0,"data":[{"provider":"a6api","name":"A6API","enabled":true,"configured":true,"logo_url":"https://a6api.com/logo.png","currency":"USD","site_url":"https://a6api.com","used_usd":2.5,"remaining_usd":8.25,"active_count":0,"subscriptions":[],"refreshed_at":"2026-09-25T03:40:12.125Z"}]}
        """.utf8)
        let statuses = try SubscriptionAPIClient.decodeStatuses(body)
        XCTAssertEqual(statuses.count, 1)
        XCTAssertEqual(statuses[0].currency, "USD")
        XCTAssertEqual(statuses[0].remainingUSD, 8.25)
        XCTAssertNotNil(statuses[0].refreshedAt)
    }

    func testDecodesRotatingTokenPairEnvelope() throws {
        let body = Data("""
        {"code":0,"data":{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600,"token_type":"Bearer"}}
        """.utf8)
        let tokens = try SubscriptionAPIClient.decodeTokenPair(body)
        XCTAssertEqual(tokens, SubscriptionTokenPair(accessToken: "new-access", refreshToken: "new-refresh", expiresIn: 3600))
    }
}
