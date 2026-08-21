import Foundation

enum Money {
    /// Formats integer cents in the given ISO currency: `$4,650`, `A$6,800`, `NZ$7,250.50`.
    static func format(cents: Int, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        formatter.locale = Locale(identifier: "en_US")
        let fraction = cents % 100 == 0 ? 0 : 2
        formatter.minimumFractionDigits = fraction
        formatter.maximumFractionDigits = fraction
        let amount = Double(cents) / 100.0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(amount)"
    }

    static func from(cents: Int, currency: String) -> String {
        "From \(format(cents: cents, currency: currency))"
    }
}

enum DateText {
    private static func formatter(_ template: String, timezone: String?) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate(template)
        if let tz = timezone, let zone = TimeZone(identifier: tz) {
            f.timeZone = zone
        }
        return f
    }

    /// "Fri, Aug 28 · 8:00 AM"
    static func departure(_ date: Date, timezone: String?) -> String {
        "\(day(date, timezone: timezone)) · \(time(date, timezone: timezone))"
    }

    /// "Fri, Aug 28"
    static func day(_ date: Date, timezone: String?) -> String {
        formatter("EEE MMM d", timezone: timezone).string(from: date)
    }

    /// "8:00 AM"
    static func time(_ date: Date, timezone: String?) -> String {
        formatter("j:mm", timezone: timezone).string(from: date)
    }

    /// "Aug 28, 2026"
    static func short(_ date: Date) -> String {
        formatter("MMM d yyyy", timezone: nil).string(from: date)
    }

    /// "14:59" countdown text for a hold expiry.
    static func countdown(to date: Date, from now: Date = Date()) -> String {
        let remaining = max(0, Int(date.timeIntervalSince(now).rounded(.down)))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
