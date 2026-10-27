import SwiftUI

/// Checks trade data quality and flags potential issues
struct DataQuality: View {
    let trades: [Trade]

    private struct Issue: Identifiable {
        let id = UUID()
        let severity: Severity
        let message: String
        let count: Int

        enum Severity {
            case warning, info

            var icon: String {
                switch self {
                case .warning: "exclamationmark.triangle.fill"
                case .info: "info.circle.fill"
                }
            }

            var color: Color {
                switch self {
                case .warning: .orange
                case .info: Color.accent
                }
            }
        }
    }

    private var issues: [Issue] {
        guard !trades.isEmpty else { return [] }
        var results: [Issue] = []

        // Check for trades with zero R-multiple (missing stop loss data)
        let zeroR = trades.filter { $0.rMultiple == 0 }.count
        if zeroR > 0 {
            results.append(Issue(severity: .warning, message: "Trades with missing R-multiple (no SL set?)", count: zeroR))
        }

        // Check for extremely large position sizes (potential data error)
        let avgShares = trades.map(\.shares).reduce(0, +) / Double(trades.count)
        let bigPositions = trades.filter { $0.shares > avgShares * 5 && avgShares > 0 }.count
        if bigPositions > 0 {
            results.append(Issue(severity: .warning, message: "Trades with 5x+ average position size", count: bigPositions))
        }

        // Check for zero-duration trades
        let zeroDuration = trades.filter { $0.durationMin == 0 }.count
        if zeroDuration > 0 {
            results.append(Issue(severity: .info, message: "Trades with 0-minute duration", count: zeroDuration))
        }

        // Check for duplicate close times (potential duplicate imports)
        let closeTimes = trades.map { $0.closeTime.timeIntervalSince1970 }
        let uniqueTimes = Set(closeTimes)
        let dupes = closeTimes.count - uniqueTimes.count
        if dupes > 0 {
            results.append(Issue(severity: .warning, message: "Trades with identical close times", count: dupes))
        }

        // Check for trades on weekends
        let weekendTrades = Self.weekendTradeCount(trades)
        if weekendTrades > 0 {
            results.append(Issue(severity: .info, message: "Trades opened on weekends", count: weekendTrades))
        }

        // Check for very large MAE relative to MFE (poor entries)
        let badEntries = trades.filter { $0.maePoints > $0.mfePoints * 3 && $0.mfePoints > 0 }.count
        if badEntries > trades.count / 4 {
            results.append(Issue(severity: .warning, message: "Trades with MAE > 3x MFE (entry quality issue)", count: badEntries))
        }

        return results
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Data Quality", systemImage: "checkmark.shield")
                    .font(.cardTitle)
                Spacer()
                if issues.isEmpty && !trades.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.semanticGreen)
                        Text("All clear")
                            .foregroundStyle(Color.semanticGreen)
                    }
                    .font(.smallText)
                }
            }

            if trades.isEmpty {
                Text("No trades to validate")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
            } else if issues.isEmpty {
                Text("No data quality issues detected across \(trades.count) trades")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(issues) { issue in
                    HStack(spacing: 6) {
                        Image(systemName: issue.severity.icon)
                            .font(.monoSmall)
                            .foregroundStyle(issue.severity.color)
                        Text(issue.message)
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("\(issue.count)")
                            .font(.monoSubtitle)
                            .fontWeight(.medium)
                            .foregroundStyle(issue.severity.color)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.borderCard, lineWidth: 1)
    )
    }
}

extension DataQuality {
    /// Trades opened on a Saturday or Sunday in New York (a Friday after-hours trade is not one)
    static func weekendTradeCount(_ trades: [Trade]) -> Int {
        trades.filter { TradingCalendar.isWeekend($0.openTime) }.count
    }
}
