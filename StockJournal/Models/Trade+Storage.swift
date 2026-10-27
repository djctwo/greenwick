import Foundation

/// The documented limits for every value Greenwick stores. The CSV import, manual entry,
/// sample data and backup restore all go through the same checks, so a crafted file can
/// never put a value in the journal that would crash or mislead an analytics screen.
enum TradeLimits {
    /// Largest share count (matches `GenericCSVParser.maxShares`)
    static let maxShares: Double = 1_000_000_000
    /// Smallest share count. Fractional shares go down to 0.000001; anything smaller is a
    /// crafted value that only exists to blow up size ratios.
    static let minShares: Double = 0.000_001
    /// Largest absolute price / P&L / commission (matches `GenericCSVParser.maxAbsAmount`)
    static let maxAbsAmount: Decimal = 1_000_000_000_000
    /// Longest holding time we accept: 20 years, in minutes
    static let maxDurationMin = 20 * 366 * 24 * 60
    /// Bound for the point-based metrics (MAE, MFE, R, range, slippage)
    static let maxAbsPoints: Double = 1_000_000_000
    /// Largest volume figure
    static let maxVolume = 1_000_000_000_000
    /// Longest free-text field (notes, checklist JSON) and longest short label
    static let maxTextLength = 100_000
    static let maxLabelLength = 200
    static let maxSymbolLength = 32
    static let maxScreenshots = 10
    /// Trade dates must fall in this window (Unix time: 1900-01-01 ... 2200-01-01)
    static let dateRange: ClosedRange<TimeInterval> = -2_208_988_800 ... 7_258_118_400
}

extension Trade {
    // MARK: - Validation

    /// Names of the fields that are outside `TradeLimits` (empty = storable as is).
    /// Text fields are only checked for length here; control characters are reported by
    /// `controlCharacterFields` and removed by `sanitizedForStorage()`.
    var storageViolations: [String] {
        var bad: [String] = []
        if !(shares.isFinite && shares >= TradeLimits.minShares && shares <= TradeLimits.maxShares) {
            bad.append("shares")
        }
        for (name, value) in [("openPrice", openPrice), ("closePrice", closePrice), ("sl", sl), ("tp", tp),
                              ("netProfit", netProfit), ("commission", commission), ("swap", swap)]
        where value.isNaN || abs(value) > TradeLimits.maxAbsAmount {
            bad.append(name)
        }
        for (name, value) in [("maePoints", maePoints), ("mfePoints", mfePoints), ("rMultiple", rMultiple),
                              ("rangeSize", rangeSize), ("slDistPoints", slDistPoints),
                              ("slippagePoints", slippagePoints)]
        where !value.isFinite || abs(value) > TradeLimits.maxAbsPoints {
            bad.append(name)
        }
        if !(0...TradeLimits.maxDurationMin).contains(durationMin) { bad.append("durationMin") }
        if !(0...TradeLimits.maxDurationMin).contains(timeToMFEMin) { bad.append("timeToMFEMin") }
        if !(0...23).contains(hour) { bad.append("hour") }
        if !(0...TradeLimits.maxVolume).contains(volume) { bad.append("volume") }
        if !(0...TradeLimits.maxVolume).contains(avgVolume) { bad.append("avgVolume") }
        if ticket <= 0 { bad.append("ticket") }
        for (name, date) in [("openTime", openTime), ("closeTime", closeTime), ("importedAt", importedAt)]
        where !TradeLimits.dateRange.contains(date.timeIntervalSince1970) {
            bad.append(name)
        }
        if symbol.isEmpty || symbol.count > TradeLimits.maxSymbolLength { bad.append("symbol") }
        for (name, text) in [("comment", comment), ("dayOfWeek", dayOfWeek), ("sector", sector),
                             ("industry", industry), ("tags", tags), ("emotion", emotion)]
        where text.count > TradeLimits.maxLabelLength {
            bad.append(name)
        }
        if notes.count > TradeLimits.maxTextLength { bad.append("notes") }
        if checklistData.count > TradeLimits.maxTextLength { bad.append("checklistData") }
        let shots = screenshotList
        if shots.count > TradeLimits.maxScreenshots
            || !shots.allSatisfy(ScreenshotManager.isValidFilename) {
            bad.append("screenshots")
        }
        return bad
    }

    /// Text fields that contain control characters (line breaks and tabs are allowed in notes)
    var controlCharacterFields: [String] {
        var bad: [String] = []
        for (name, text) in [("symbol", symbol), ("comment", comment), ("dayOfWeek", dayOfWeek),
                             ("sector", sector), ("industry", industry), ("tags", tags),
                             ("emotion", emotion), ("screenshots", screenshots), ("checklistData", checklistData)]
        where text.containsControlCharacters(allowingLineBreaks: false) {
            bad.append(name)
        }
        if notes.containsControlCharacters(allowingLineBreaks: true) { bad.append("notes") }
        return bad
    }

    // MARK: - Sanitizing

    /// A comma-separated screenshot list with only the app's own filenames kept
    static func validScreenshotList(_ raw: String) -> String {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter(ScreenshotManager.isValidFilename)
            .prefix(TradeLimits.maxScreenshots)
            .joined(separator: ",")
    }

    /// The trade as it may be stored, or nil when a number is outside `TradeLimits`.
    /// Control characters are stripped from text and unknown screenshot names dropped.
    func sanitizedForStorage() -> Trade? {
        var t = self
        t.symbol = symbol.removingControlCharacters(keepingLineBreaks: false)
        t.comment = comment.removingControlCharacters(keepingLineBreaks: false)
        t.dayOfWeek = dayOfWeek.removingControlCharacters(keepingLineBreaks: false)
        t.sector = sector.removingControlCharacters(keepingLineBreaks: false)
        t.industry = industry.removingControlCharacters(keepingLineBreaks: false)
        t.tags = tags.removingControlCharacters(keepingLineBreaks: false)
        t.emotion = emotion.removingControlCharacters(keepingLineBreaks: false)
        t.checklistData = checklistData.removingControlCharacters(keepingLineBreaks: false)
        t.notes = notes.removingControlCharacters(keepingLineBreaks: true)
        t.screenshots = Self.validScreenshotList(screenshots)
        return t.storageViolations.isEmpty ? t : nil
    }
}

extension String {
    /// True if the string holds a C0/C1 control character (or a line break, unless allowed)
    func containsControlCharacters(allowingLineBreaks: Bool) -> Bool {
        unicodeScalars.contains { Self.isDisallowedControl($0, allowingLineBreaks: allowingLineBreaks) }
    }

    /// The string without control characters (line breaks and tabs kept if asked)
    func removingControlCharacters(keepingLineBreaks: Bool) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: unicodeScalars.filter {
            !Self.isDisallowedControl($0, allowingLineBreaks: keepingLineBreaks)
        })
        return String(scalars)
    }

    private static func isDisallowedControl(_ scalar: Unicode.Scalar, allowingLineBreaks: Bool) -> Bool {
        if allowingLineBreaks, scalar == "\n" || scalar == "\t" { return false }
        return scalar.properties.generalCategory == .control
            || scalar == "\u{2028}" || scalar == "\u{2029}" // line/paragraph separators
    }
}
