import Foundation
import os

/// Exports trade data as CSV for spreadsheet analysis
final class CSVExporter: Sendable {
    private static let logger = Logger(subsystem: "com.greenwick", category: "CSVExporter")

    /// Column headers for the export
    private static let headers = [
        "Ticket", "Symbol", "Direction", "Shares",
        "Open Time", "Close Time", "Duration (min)",
        "Open Price", "Close Price", "SL", "TP",
        "Net Profit", "MAE (points)", "MFE (points)", "R-Multiple",
        "Session", "Day", "Hour",
        "Range Size", "Hit BE", "Scaled In", "Trading Day (ET)"
    ]

    /// Export trades as CSV file
    func export(trades: [Trade], to url: URL) throws {
        let content = buildCSVContent(trades: trades)
        try content.write(to: url, atomically: true, encoding: .utf8)
        Self.logger.info("CSV exported \(trades.count) trades")
    }

    // MARK: - Private

    /// Build CSV string from trades
    private func buildCSVContent(trades: [Trade]) -> String {
        var lines: [String] = []
        lines.append(Self.headers.joined(separator: ","))

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        for trade in trades {
            let row = [
                String(trade.ticket),
                trade.symbol,
                trade.direction.rawValue,
                String(format: "%.0f", trade.shares),
                dateFormatter.string(from: trade.openTime),
                dateFormatter.string(from: trade.closeTime),
                String(trade.durationMin),
                "\(trade.openPrice)",
                "\(trade.closePrice)",
                "\(trade.sl)",
                "\(trade.tp)",
                "\(trade.netProfit)",
                String(format: "%.2f", trade.maePoints),
                String(format: "%.2f", trade.mfePoints),
                String(format: "%.2f", trade.rMultiple),
                trade.session.rawValue,
                trade.entryWeekday,  // "Day" and "Hour" describe the entry, in ET
                String(trade.hour),
                String(format: "%.1f", trade.rangeSize),
                trade.hitBreakeven ? "YES" : "NO",
                trade.scaledIn ? "YES" : "NO",
                TradingCalendar.dayKey(trade.closeTime)
            ].map { Self.sanitizeCSVField($0) }
            lines.append(row.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    /// Sanitize a field for safe CSV output: control characters (CR, LF, tab, NUL, ESC...)
    /// are removed so nothing can split a row, formula prefixes are neutralised, and fields
    /// with commas, quotes or line breaks are quoted.
    static func sanitizeCSVField(_ field: String) -> String {
        var value = field.removingControlCharacters(keepingLineBreaks: false)
        // Prevent CSV formula injection — prefix dangerous characters with single quote
        if let first = value.first, "=+@-\t\r".contains(first) {
            value = "'" + value
        }
        // Quote fields containing commas, quotes, or line breaks (CR as well as LF)
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            value = "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
