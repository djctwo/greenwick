import SwiftUI

/// Portfolio diversification quality analysis using effective position count,
/// concentration risk, sector distribution, and a letter grade.
struct DiversificationScore: View {
    let trades: [Trade]

    // MARK: - Analysis Models

    private enum Grade: String {
        case a = "A"
        case b = "B"
        case c = "C"
        case d = "D"
        case f = "F"

        var color: Color {
            switch self {
            case .a: Color.semanticGreen
            case .b: Color.semanticGreen.opacity(0.8)
            case .c: Color.semanticAmber
            case .d: Color.semanticAmber
            case .f: Color.semanticRed
            }
        }

        var label: String {
            switch self {
            case .a: "Excellent"
            case .b: "Good"
            case .c: "Fair"
            case .d: "Poor"
            case .f: "Concentrated"
            }
        }
    }

    // MARK: - Sector Colors

    private static let sectorColors: [Color] = [
        .semanticBlue, .semanticPurple, .semanticAmber, .semanticCyan,
        .semanticGreen, .semanticRed,
        .accent, .semanticCyan, .semanticPurple, .semanticBlue,
    ]

    // MARK: - Pearson Correlation (self-contained, same algorithm as SymbolCorrelation)

    private var symbols: [String] {
        Array(Set(trades.map(\.symbol))).sorted()
    }

    /// Daily P&L series per symbol
    private var symbolDailyPnL: [String: [String: Double]] {
        var result: [String: [String: Double]] = [:]
        for symbol in symbols { result[symbol] = [:] }
        for trade in trades {
            let dateKey = TradingCalendar.dayKey(trade.closeTime)
            result[trade.symbol, default: [:]][dateKey, default: 0] += trade.profitDouble
        }
        return result
    }

    /// Full NxN correlation matrix
    private var correlationMatrix: [[Double]] {
        guard symbols.count >= 2 else {
            return symbols.isEmpty ? [] : [[1.0]]
        }

        let symbolData = symbolDailyPnL
        let allDates = Set(symbolData.values.flatMap(\.keys))
        var matrix = Array(repeating: Array(repeating: 0.0, count: symbols.count), count: symbols.count)

        for i in 0..<symbols.count {
            for j in 0..<symbols.count {
                if i == j {
                    matrix[i][j] = 1.0
                } else if j > i {
                    let corr = pearsonCorrelation(
                        series1: symbolData[symbols[i]] ?? [:],
                        series2: symbolData[symbols[j]] ?? [:],
                        dates: allDates
                    )
                    matrix[i][j] = corr
                    matrix[j][i] = corr
                }
            }
        }
        return matrix
    }

    private func pearsonCorrelation(series1: [String: Double], series2: [String: Double], dates: Set<String>) -> Double {
        let commonDates = dates.filter { series1[$0] != nil && series2[$0] != nil }
        guard commonDates.count >= 2 else { return 0 }

        let x = commonDates.compactMap { series1[$0] }
        let y = commonDates.compactMap { series2[$0] }
        guard x.count == y.count, x.count == commonDates.count else { return 0 }
        let n = Double(x.count)

        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n

        var sumXY = 0.0, sumX2 = 0.0, sumY2 = 0.0
        for i in 0..<x.count {
            let dx = x[i] - meanX
            let dy = y[i] - meanY
            sumXY += dx * dy
            sumX2 += dx * dx
            sumY2 += dy * dy
        }

        let denominator = sqrt(sumX2 * sumY2)
        guard denominator > 0 else { return 0 }
        return sumXY / denominator
    }

    // MARK: - Effective Position Count

    /// N^2 / sum(all correlations^2) — measures how many truly independent bets exist
    private var effectivePositionCount: Double {
        let matrix = correlationMatrix
        let n = symbols.count
        guard n >= 2, matrix.count == n else { return Double(n) }

        var sumCorrSq = 0.0
        for i in 0..<n {
            for j in 0..<n {
                sumCorrSq += matrix[i][j] * matrix[i][j]
            }
        }

        guard sumCorrSq > 0 else { return Double(n) }
        return Double(n * n) / sumCorrSq
    }

    // MARK: - Concentration Risk

    private var topSymbolsByPnL: [(symbol: String, pnl: Double, pct: Double)] {
        let totalAbsPnL = trades.map { abs($0.profitDouble) }.reduce(0, +)
        guard totalAbsPnL > 0 else { return [] }

        let bySymbol = Dictionary(grouping: trades, by: \.symbol)
        let symbolPnL = bySymbol.map { symbol, symbolTrades -> (String, Double) in
            let total = symbolTrades.map(\.profitDouble).reduce(0, +)
            return (symbol, total)
        }
        .sorted { abs($0.1) > abs($1.1) }

        return symbolPnL.prefix(5).map { symbol, pnl in
            (symbol: symbol, pnl: pnl, pct: abs(pnl) / totalAbsPnL * 100)
        }
    }

    // MARK: - Sector Distribution

    private var sectorDistribution: [(sector: String, count: Int, pct: Double)] {
        let withSector = trades.filter { !$0.sector.isEmpty }
        guard !withSector.isEmpty else { return [] }

        let bySector = Dictionary(grouping: withSector, by: \.sector)
        let total = Double(withSector.count)

        return bySector.map { sector, sectorTrades in
            (sector: sector, count: sectorTrades.count, pct: Double(sectorTrades.count) / total * 100)
        }
        .sorted { $0.count > $1.count }
    }

    // MARK: - Grade

    private func computeGrade(effectiveCount: Double, actualCount: Int, topSectors: [(sector: String, count: Int, pct: Double)]) -> Grade {
        guard actualCount > 0 else { return .f }
        let ratio = effectiveCount / Double(actualCount)
        let maxSectorPct = topSectors.first?.pct ?? 0

        if ratio > 0.7 && maxSectorPct <= 40 { return .a }
        if ratio > 0.5 { return .b }
        if ratio > 0.3 { return .c }
        if ratio > 0.2 { return .d }
        return .f
    }

    // MARK: - Body

    var body: some View {
        if trades.count < 10 || symbols.count < 2 {
            EmptyView()
        } else {
            let effective = effectivePositionCount
            let actualCount = symbols.count
            let topSymbols = topSymbolsByPnL
            let sectors = sectorDistribution
            let grade = computeGrade(
                effectiveCount: effective,
                actualCount: actualCount,
                topSectors: sectors
            )

            VStack(alignment: .leading, spacing: 16) {
                header(grade: grade)
                effectivePositionSection(effective: effective, actual: actualCount)
                concentrationSection(topSymbols: topSymbols)

                if !sectors.isEmpty {
                    sectorSection(sectors: sectors)
                }

                gradeSection(grade: grade, effective: effective, actual: actualCount, sectors: sectors)
            }
            .padding(16)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderCard, lineWidth: 1))
        }
    }

    // MARK: - Header

    private func header(grade: Grade) -> some View {
        HStack {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentDim)
                        .frame(width: 22, height: 22)
                    Image(systemName: "circle.grid.cross")
                        .font(.smallText)
                        .foregroundStyle(Color.accent)
                }
                Text("Diversification Score")
                    .font(.cardTitle)
            }
            Spacer()
            Text(grade.rawValue)
                .font(.kpiValueSecondary)
                .foregroundStyle(grade.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(grade.color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Effective Position Count

    private func effectivePositionSection(effective: Double, actual: Int) -> some View {
        let ratio = effective / Double(actual)
        let quality: (color: Color, label: String)
        if ratio > 0.7 {
            quality = (Color.semanticGreen, "Well diversified")
        } else if ratio > 0.4 {
            quality = (Color.semanticAmber, "Moderately diversified")
        } else {
            quality = (Color.semanticRed, "Concentrated")
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text("EFFECTIVE POSITION COUNT")
                .font(.monoSubtitle)
                .foregroundStyle(Color.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", effective))
                    .font(.kpiValueSecondary)
                    .foregroundStyle(quality.color)
                Text("effective positions out of \(actual) symbols")
                    .font(.bodyText)
                    .foregroundStyle(Color.textSecondary)
            }

            // Progress bar visualization
            GeometryReader { geometry in
                let barWidth = geometry.size.width
                let fillRatio = min(ratio, 1.0)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.bgInset)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(quality.color)
                        .frame(width: barWidth * fillRatio, height: 8)
                }
            }
            .frame(height: 8)

            HStack(spacing: 4) {
                Circle().fill(quality.color).frame(width: 6, height: 6)
                Text(quality.label)
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(12)
        .background(Color.bgInset)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderCard, lineWidth: 1))
    }

    // MARK: - Concentration Risk

    private func concentrationSection(topSymbols: [(symbol: String, pnl: Double, pct: Double)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONCENTRATION RISK")
                .font(.monoSubtitle)
                .foregroundStyle(Color.textSecondary)

            let maxPct = topSymbols.first?.pct ?? 0

            ForEach(Array(topSymbols.prefix(3).enumerated()), id: \.element.symbol) { index, item in
                HStack(spacing: 8) {
                    Text(item.symbol)
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 60, alignment: .leading)

                    // Bar
                    GeometryReader { geometry in
                        let barWidth = geometry.size.width
                        let fillWidth = barWidth * (item.pct / max(maxPct, 1))

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.bgInset)
                                .frame(height: 14)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(item.pct > 40 ? Color.semanticRed.opacity(0.7) : Color.accent.opacity(0.5))
                                .frame(width: max(fillWidth, 2), height: 14)
                        }
                    }
                    .frame(height: 14)

                    Text(String(format: "%.0f%%", item.pct))
                        .font(.monoSmall)
                        .foregroundStyle(item.pct > 40 ? Color.semanticRed : Color.textSecondary)
                        .frame(width: 36, alignment: .trailing)

                    Text(String(format: "%+.0f", item.pnl))
                        .font(.monoSmall)
                        .foregroundStyle(Color.forPnL(item.pnl))
                        .frame(width: 50, alignment: .trailing)
                }
            }

            // Warning for heavy concentration
            if let top = topSymbols.first, top.pct > 40 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.smallText)
                        .foregroundStyle(Color.semanticAmber)
                    Text("Heavy concentration in \(top.symbol) (\(String(format: "%.0f%%", top.pct)) of total P&L)")
                        .font(.smallText)
                        .foregroundStyle(Color.semanticAmber)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.semanticAmberDim)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Sector Distribution

    private func sectorSection(sectors: [(sector: String, count: Int, pct: Double)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SECTOR DISTRIBUTION")
                .font(.monoSubtitle)
                .foregroundStyle(Color.textSecondary)

            let maxPct = sectors.first?.pct ?? 0

            ForEach(Array(sectors.enumerated()), id: \.element.sector) { index, item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Self.sectorColors[index % Self.sectorColors.count])
                        .frame(width: 8, height: 8)

                    Text(item.sector)
                        .font(.smallText)
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 100, alignment: .leading)
                        .lineLimit(1)

                    // Horizontal bar
                    GeometryReader { geometry in
                        let barWidth = geometry.size.width
                        let fillWidth = barWidth * (item.pct / max(maxPct, 1))

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.bgInset)
                                .frame(height: 12)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(Self.sectorColors[index % Self.sectorColors.count].opacity(0.6))
                                .frame(width: max(fillWidth, 2), height: 12)
                        }
                    }
                    .frame(height: 12)

                    Text(String(format: "%.0f%%", item.pct))
                        .font(.monoSmall)
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 36, alignment: .trailing)

                    Text("\(item.count)")
                        .font(.monoSmall)
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 28, alignment: .trailing)
                }
            }

            // Warning for sector concentration
            if let top = sectors.first, top.pct > 60 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.smallText)
                        .foregroundStyle(Color.semanticAmber)
                    Text("Consider diversifying beyond \(top.sector) (\(String(format: "%.0f%%", top.pct)) of trades)")
                        .font(.smallText)
                        .foregroundStyle(Color.semanticAmber)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.semanticAmberDim)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Grade Section

    private func gradeSection(grade: Grade, effective: Double, actual: Int, sectors: [(sector: String, count: Int, pct: Double)]) -> some View {
        let ratio = effective / Double(actual)
        let topSectorPct = sectors.first?.pct ?? 0

        let details: String
        switch grade {
        case .a:
            details = "Strong diversification. \(String(format: "%.0f%%", ratio * 100)) effective independence across \(actual) symbols with no sector exceeding 40%."
        case .b:
            details = "Good spread. \(String(format: "%.0f%%", ratio * 100)) effective independence. Minor concentration could be improved."
        case .c:
            details = "Moderate concentration. Only \(String(format: "%.1f", effective)) effective independent positions from \(actual) symbols. Returns are correlated."
        case .d:
            details = "High concentration risk. Your \(actual) symbols behave like \(String(format: "%.1f", effective)) independent positions. Drawdowns will be amplified."
        case .f:
            if topSectorPct > 60 {
                details = "Extreme concentration. \(String(format: "%.0f%%", topSectorPct)) in one sector with highly correlated positions. A single adverse event could impact most of your portfolio."
            } else {
                details = "Extreme concentration. Your symbols move together, providing almost no diversification benefit."
            }
        }

        return HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(grade.rawValue)
                    .font(.kpiValue)
                    .foregroundStyle(grade.color)
                Text(grade.label)
                    .font(.monoSmall)
                    .foregroundStyle(grade.color)
            }
            .frame(width: 70)

            Text(details)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(grade.color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(grade.color.opacity(0.15), lineWidth: 1))
    }
}
