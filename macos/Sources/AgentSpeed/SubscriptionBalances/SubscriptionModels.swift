import Foundation

struct SubscriptionBalanceStatus: Codable, Identifiable, Hashable {
    let provider: String
    let name: String
    let enabled: Bool
    let configured: Bool
    let currency: String
    let siteURL: String
    let errorCode: String?
    let errorMessage: String?
    let totalLimitUSD: Double?
    let usedUSD: Double
    let remainingUSD: Double?
    let refreshedAt: Date?

    var id: String { provider }

    enum CodingKeys: String, CodingKey {
        case provider, name, enabled, configured, currency
        case siteURL = "site_url"
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case totalLimitUSD = "total_limit_usd"
        case usedUSD = "used_usd"
        case remainingUSD = "remaining_usd"
        case refreshedAt = "refreshed_at"
    }
}

enum SubscriptionBalanceMode: String, CaseIterable, Identifiable {
    case selected = "selected"
    case total = "total"
    case rotation = "rotation"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selected: return "Selected balance"
        case .total: return "Total by currency"
        case .rotation: return "Rotate selected"
        }
    }
}

struct SubscriptionCurrencyTotal: Identifiable {
    let currency: String
    let amount: Double
    var id: String { currency }
}

enum SubscriptionMoneyFormatter {
    static func string(amount: Double, currency: String) -> String {
        let normalized = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = normalized.isEmpty ? "USD" : normalized
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        if let value = formatter.string(from: NSNumber(value: amount)) {
            return value
        }
        return "\(normalized) \(amount.formatted(.number.precision(.fractionLength(0...2))))"
    }

    static func compact(amount: Double, currency: String) -> String {
        let normalized = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let symbol: String
        switch normalized {
        case "USD": symbol = "$"
        case "CNY", "RMB": symbol = "¥"
        case "EUR": symbol = "€"
        case "GBP": symbol = "£"
        default: symbol = normalized.isEmpty ? "" : "\(normalized) "
        }
        return "\(symbol)\(amount.formatted(.number.precision(.fractionLength(0...2))))"
    }
}
