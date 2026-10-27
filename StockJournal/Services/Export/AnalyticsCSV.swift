import AppKit
import Foundation
import UniformTypeIdentifiers

/// CSV exports of the analytics cards (What to Cut, Kill Zones). The user picks where the
/// file goes; nothing is written to a temporary folder (the journal's figures never sit
/// unencrypted anywhere the user didn't choose).
enum AnalyticsCSV {
    /// CSV text for `rows` (the first row is the header). Labels such as tickers and
    /// sectors come from imported files, so every field that isn't a plain number goes
    /// through `CSVExporter.sanitizeCSVField` (formula prefixes, commas, control characters).
    static func content(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { Double($0) != nil ? $0 : CSVExporter.sanitizeCSVField($0) }.joined(separator: ",")
        }.joined(separator: "\n")
    }

    /// Ask where to save `rows`, then write them. Returns the file, or nil if cancelled.
    @MainActor
    static func save(_ rows: [[String]], suggestedName: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try content(rows).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
