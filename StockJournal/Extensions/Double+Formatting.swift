import Foundation

extension Double {
    /// Cached currency formatter (NumberFormatter is expensive to create)
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()

    /// Format as currency: "$1,234.56" or "-$1,234.56"
    var asCurrency: String {
        Self.currencyFormatter.string(from: NSNumber(value: self)) ?? "$0.00"
    }

    /// Format as points: "12.5 pts"
    var asPoints: String {
        String(format: "%.1f pts", self)
    }

    /// Format as percentage: "65.4%"
    var asPercent: String {
        String(format: "%.1f%%", self)
    }

    /// Format as R-multiple: "1.5R" or "-0.3R"
    var asRMultiple: String {
        String(format: "%.2fR", self)
    }

    /// Format as profit factor: "1.85"
    var asProfitFactor: String {
        if self.isInfinite { return "99.99" }
        return String(format: "%.2f", self)
    }

    /// Compact currency for large values: "$1.2K", "$15.3K"
    var asCompactCurrency: String {
        let abs = Swift.abs(self)
        let sign = self < 0 ? "-" : ""
        if abs >= 1_000_000 {
            return "\(sign)$\(String(format: "%.1fM", abs / 1_000_000))"
        } else if abs >= 1_000 {
            return "\(sign)$\(String(format: "%.1fK", abs / 1_000))"
        }
        return asCurrency
    }
}

extension Decimal {
    /// Format as currency: "$1,234.56"
    var asCurrency: String {
        NSDecimalNumber(decimal: self).doubleValue.asCurrency
    }
}
