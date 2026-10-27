import Foundation

// MARK: - Overflow-safe integer conversions

extension Int {
    /// Converts a Double without trapping: NaN becomes 0, and values beyond the Int range
    /// (including ±infinity) become `Int.max` / `Int.min`. Use this instead of `Int(x)`
    /// wherever `x` is derived from stored or imported trade data.
    init(saturating value: Double) {
        if value.isNaN {
            self = 0
        } else if value >= 9_223_372_036_854_775_807.0 { // == 2^63 as a Double
            self = .max
        } else if value <= -9_223_372_036_854_775_808.0 {
            self = .min
        } else {
            self = Int(value)
        }
    }
}

extension Sequence where Element == Int {
    /// Sum that stops at `Int.max` / `Int.min` instead of trapping on overflow
    func saturatingSum() -> Int {
        reduce(0) { total, value in
            let (sum, overflow) = total.addingReportingOverflow(value)
            if overflow { return value > 0 ? .max : .min }
            return sum
        }
    }

    /// Integer average computed in Double (cannot overflow); 0 for an empty sequence
    func overflowSafeAverage() -> Int {
        var total = 0.0
        var count = 0
        for value in self {
            total += Double(value)
            count += 1
        }
        guard count > 0 else { return 0 }
        return Int(saturating: total / Double(count))
    }
}
