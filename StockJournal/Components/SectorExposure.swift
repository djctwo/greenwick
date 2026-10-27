import SwiftUI

/// Shows P&L distribution by sector with horizontal bar chart and concentration warnings
struct SectorExposure: View {
    let trades: [Trade]

    // MARK: - Computed Data

    private struct SectorStats: Identifiable {
        let id: String
        var sector: String { id }
        let totalPnL: Double
        let tradeCount: Int
        let winRate: Double
    }

    private var sectorStats: [SectorStats] {
        let withSector = trades.filter { !$0.sector.isEmpty }
        let grouped = Dictionary(grouping: withSector) { $0.sector }

        return grouped.map { sector, sectorTrades in
            let totalPnL = sectorTrades.reduce(0.0) { $0 + $1.profitDouble }
            let wins = sectorTrades.filter(\.isWin).count
            let winRate = sectorTrades.isEmpty ? 0 : Double(wins) / Double(sectorTrades.count) * 100
            return SectorStats(
                id: sector,
                totalPnL: totalPnL,
                tradeCount: sectorTrades.count,
                winRate: winRate
            )
        }
        .sorted { abs($0.totalPnL) > abs($1.totalPnL) }
    }

    private var hasSectorData: Bool {
        trades.contains { !$0.sector.isEmpty }
    }

    private var maxAbsPnL: Double {
        sectorStats.map { abs($0.totalPnL) }.max() ?? 1
    }

    private var concentrationWarning: String? {
        let withSector = trades.filter { !$0.sector.isEmpty }
        guard !withSector.isEmpty else { return nil }
        let grouped = Dictionary(grouping: withSector) { $0.sector }
        let totalCount = withSector.count

        for (sector, sectorTrades) in grouped {
            let pct = Double(sectorTrades.count) / Double(totalCount) * 100
            if pct > 50 {
                return "\(sector) accounts for \(String(format: "%.0f", pct))% of trades — consider diversifying"
            }
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sector Exposure", systemImage: "chart.pie")
                .font(.cardTitle)

            if !hasSectorData {
                Text("Add sector data to trades for exposure analysis")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                // Concentration warning
                if let warning = concentrationWarning {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.semanticAmber)
                            .font(.smallText)
                        Text(warning)
                            .font(.smallText)
                            .foregroundStyle(Color.semanticAmber)
                    }
                }

                // Horizontal bar chart
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sectorStats) { stat in
                        sectorRow(stat)
                    }
                }

                // Summary
                let totalPnL = sectorStats.reduce(0.0) { $0 + $1.totalPnL }
                HStack {
                    Text("Total")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(totalPnL.asCurrency)
                        .font(.monoSubtitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.forPnL(totalPnL))
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderCard, lineWidth: 1))
    }

    // MARK: - Subviews

    private func sectorRow(_ stat: SectorStats) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Sector name and stats
            HStack {
                Text(stat.sector)
                    .font(.smallText)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text("\(stat.tradeCount)t")
                    .font(.monoSmall)
                    .foregroundStyle(Color.textTertiary)

                Text(stat.winRate.asPercent)
                    .font(.monoSmall)
                    .foregroundStyle(Color.textSecondary)

                Text(stat.totalPnL.asCurrency)
                    .font(.monoSubtitle)
                    .foregroundStyle(Color.forPnL(stat.totalPnL))
            }

            // Horizontal bar
            GeometryReader { geo in
                let midX = geo.size.width / 2
                let barWidth = maxAbsPnL > 0
                    ? CGFloat(abs(stat.totalPnL) / maxAbsPnL) * midX
                    : 0

                ZStack(alignment: .leading) {
                    // Center line
                    Rectangle()
                        .fill(Color.borderSubtle)
                        .frame(width: 1)
                        .position(x: midX, y: geo.size.height / 2)

                    // Bar
                    if stat.totalPnL >= 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.semanticGreen.opacity(0.7))
                            .frame(width: barWidth, height: 8)
                            .offset(x: midX)
                    } else {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.semanticRed.opacity(0.7))
                            .frame(width: barWidth, height: 8)
                            .offset(x: midX - barWidth)
                    }
                }
            }
            .frame(height: 10)
        }
    }
}
