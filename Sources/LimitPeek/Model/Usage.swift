import Foundation

// Wire format of GET /api/oauth/usage, decoded with .convertFromSnakeCase.
// Almost everything is optional: unused buckets come back null, and the set of
// bucket names grows over time.

struct UsageResponse: Decodable, Sendable {
    /// Preferred source: ordered, and new kinds appear here on their own.
    var limits: [LimitEntry] = []

    // Fallback for responses where `limits` is empty.
    var fiveHour: RateWindow?
    var sevenDay: RateWindow?
    var sevenDayOpus: RateWindow?
    var sevenDaySonnet: RateWindow?

    var spend: Spend?
}

struct RateWindow: Decodable, Sendable {
    /// Already 0–100, not 0–1.
    var utilization: Double?
    var resetsAt: Date?
}

struct LimitEntry: Decodable, Sendable {
    var kind: String
    /// Already 0–100.
    var percent: Double
    var severity: Severity?
    var resetsAt: Date?
    var scope: Scope?

    struct Scope: Decodable, Sendable {
        var model: Label?

        struct Label: Decodable, Sendable {
            var displayName: String
        }
    }
}

/// Usage credits. Money arrives in minor units, hence Decimal, not Double.
struct Spend: Decodable, Sendable {
    var used: Money?
    var limit: Money?
    var percent: Double?
    var severity: Severity?
    var enabled: Bool?

    struct Money: Decodable, Sendable {
        var amountMinor: Int
        var currency: String?
        var exponent: Int

        var amount: Decimal {
            Decimal(amountMinor) / pow(Decimal(10), exponent)
        }
    }
}

enum Severity: String, Decodable, Sendable {
    case normal, warning, critical
    // Unknown severities degrade rather than failing the decode.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Severity(rawValue: raw) ?? .normal
    }
}
