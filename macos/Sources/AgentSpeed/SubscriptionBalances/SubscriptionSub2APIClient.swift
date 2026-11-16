import Foundation

enum SubscriptionAPIError: LocalizedError {
    case invalidBaseURL
    case unauthorized
    case server(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: return "Sub2API URL is invalid"
        case .unauthorized: return "Sub2API access token is invalid or expired"
        case .server(let status): return "Sub2API returned HTTP \(status)"
        case .invalidResponse: return "Sub2API returned an invalid response"
        }
    }
}

struct SubscriptionTokenPair: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

struct SubscriptionAPIClient {
    var session: URLSession = .shared
    func fetchStatuses(baseURL: String, apiKey: String) async throws -> [SubscriptionBalanceStatus] {
        guard let url = Self.statusesURL(baseURL: baseURL) else { throw SubscriptionAPIError.invalidBaseURL }
        let data = try await get(url: url, apiKey: apiKey)
        return try Self.decodeStatuses(data)
    }

    func fetchStatuses(baseURL: String, token: String) async throws -> [SubscriptionBalanceStatus] {
        guard let url = Self.statusesURL(baseURL: baseURL, forceRefresh: true) else { throw SubscriptionAPIError.invalidBaseURL }
        let data = try await get(url: url, token: token)
        return try Self.decodeStatuses(data)
    }

    func refreshAccessToken(baseURL: String, refreshToken: String) async throws -> SubscriptionTokenPair {
        guard let url = Self.refreshURL(baseURL: baseURL) else { throw SubscriptionAPIError.invalidBaseURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AgentSpeed/1.8.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SubscriptionAPIError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw SubscriptionAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw SubscriptionAPIError.server(http.statusCode) }
        return try Self.decodeTokenPair(data)
    }

    private func get(url: URL, token: String? = nil, apiKey: String? = nil) async throws -> Data {

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AgentSpeed/1.8.0", forHTTPHeaderField: "User-Agent")
        if let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        } else if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SubscriptionAPIError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw SubscriptionAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw SubscriptionAPIError.server(http.statusCode) }
        return data
    }

    static func statusesURL(baseURL: String, forceRefresh: Bool = false) -> URL? {
        endpointURL(baseURL: baseURL, endpoint: "external-subscriptions/statuses", forceRefresh: forceRefresh)
    }

    static func refreshURL(baseURL: String) -> URL? {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme, ["http", "https"].contains(scheme.lowercased()),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil else { return nil }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let apiPrefix = path.hasSuffix("api/v1") ? path : (path.isEmpty ? "api/v1" : path + "/api/v1")
        components.path = "/\(apiPrefix)/auth/refresh"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func endpointURL(baseURL: String, endpoint: String, forceRefresh: Bool = false) -> URL? {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme, ["http", "https"].contains(scheme.lowercased()),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil else { return nil }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let apiPrefix = path.hasSuffix("api/v1") ? path : (path.isEmpty ? "api/v1" : path + "/api/v1")
        components.path = "/\(apiPrefix)/admin/\(endpoint.hasPrefix("external-subscriptions") ? endpoint : "external-subscriptions/\(endpoint)")"
        components.fragment = nil
        components.queryItems = forceRefresh ? [URLQueryItem(name: "refresh", value: "1")] : nil
        return components.url
    }

    static func decodeStatuses(_ data: Data) throws -> [SubscriptionBalanceStatus] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid ISO-8601 date")
        }
        if let direct = try? decoder.decode([SubscriptionBalanceStatus].self, from: data) { return direct }
        struct Envelope: Decodable { let data: [SubscriptionBalanceStatus] }
        if let wrapped = try? decoder.decode(Envelope.self, from: data) { return wrapped.data }
        throw SubscriptionAPIError.invalidResponse
    }

    static func decodeTokenPair(_ data: Data) throws -> SubscriptionTokenPair {
        let decoder = JSONDecoder()
        if let direct = try? decoder.decode(SubscriptionTokenPair.self, from: data) {
            return direct
        }
        struct Envelope: Decodable { let data: SubscriptionTokenPair }
        if let wrapped = try? decoder.decode(Envelope.self, from: data) {
            return wrapped.data
        }
        throw SubscriptionAPIError.invalidResponse
    }
}
