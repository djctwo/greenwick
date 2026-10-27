import SwiftUI

/// Structured trading setup analytics — extends the tag system into a playbook.
/// Each unique tag becomes a "setup" with full performance metrics and Keep/Review/Drop classification.
struct PlaybookCatalog: View {
    let trades: [Trade]

    // MARK: - Setup Data Model

    private struct SetupData: Identifiable {
        let id: String
        let name: String
        let trades: [Trade]
        let tradeCount: Int
        let winRate: Double
        let avgR: Double
        let profitFactor: Double
        let totalPnL: Double
        let bestSession: MarketSession?
        let worstSession: MarketSession?
        let recentPnL: [Double] // Last 10 trades P&L for sparkline
        let classification: Classification
    }

    private enum Classification: String {
        case keep = "KEEP"
        case review = "REVIEW"
        case drop = "DROP"

        var color: Color {
            switch self {
            case .keep: Color.semanticGreen
            case .review: .orange
            case .drop: Color.semanticRed
            }
        }

        var icon: String {
            switch self {
            case .keep: "checkmark.seal.fill"
            case .review: "exclamationmark.triangle.fill"
            case .drop: "xmark.seal.fill"
            }
        }
    }

    // MARK: - Computed Data

    private var setups: [SetupData] {
        // Build tag -> [Trade] mapping
        var tagTrades: [String: [Trade]] = [:]
        for trade in trades {
            for tag in trade.tagList {
                tagTrades[tag, default: []].append(trade)
            }
        }

        return tagTrades.map { tag, tagged in
            let sorted = tagged.sorted { $0.closeTime < $1.closeTime }
            let count = tagged.count
            let wins = tagged.filter(\.isWin).count
            let winRate = Double(wins) / Double(count) * 100
            let avgR = tagged.map(\.rMultiple).reduce(0, +) / Double(count)
            let totalPnL = tagged.reduce(0.0) { $0 + $1.profitDouble }

            // Profit factor
            let grossWin = tagged.filter(\.isWin).map(\.profitDouble).reduce(0, +)
            let grossLoss = abs(tagged.filter(\.isLoss).map(\.profitDouble).reduce(0, +))
            let pf = grossLoss > 0 ? grossWin / grossLoss : (grossWin > 0 ? .infinity : 0)

            // Best/worst session for this setup
            let sessionGroups = Dictionary(grouping: tagged) { $0.session }
            let sessionPnL = sessionGroups.mapValues { $0.reduce(0.0) { $0 + $1.profitDouble } }
            let bestSession = sessionPnL.max(by: { $0.value < $1.value })?.key
            let worstSession = sessionPnL.min(by: { $0.value < $1.value })?.key

            // Last 10 trades P&L for sparkline
            let recentPnL = sorted.suffix(10).map(\.profitDouble)

            // Classification logic
            let classification: Classification
            let effectivePF = pf.isInfinite ? 99.99 : pf
            if effectivePF >= 1.0 && count >= 5 {
                classification = .keep
            } else if effectivePF < 0.8 && count >= 5 {
                classification = .drop
            } else {
                classification = .review
            }

            return SetupData(
                id: tag,
                name: tag,
                trades: tagged,
                tradeCount: count,
                winRate: winRate,
                avgR: avgR,
                profitFactor: effectivePF,
                totalPnL: totalPnL,
                bestSession: bestSession,
                worstSession: worstSession,
                recentPnL: recentPnL,
                classification: classification
            )
        }.sorted { abs($0.totalPnL) > abs($1.totalPnL) }
    }

    private var keepSetups: [SetupData] { setups.filter { $0.classification == .keep } }
    private var reviewSetups: [SetupData] { setups.filter { $0.classification == .review } }
    private var dropSetups: [SetupData] { setups.filter { $0.classification == .drop } }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Label("Playbook Catalog", systemImage: "book.pages")
                    .font(.cardTitle)
                Spacer()
                Text("\(setups.count) setups tracked")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
            }

            if setups.isEmpty {
                emptyState
            } else {
                // Summary bar
                summaryBar

                // Setup cards
                setupCardsSection

                // Keep vs Drop ranking
                rankingSection
            }
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
       .overlay(
           RoundedRectangle(cornerRadius: 12)
               .stroke(Color.borderCard, lineWidth: 1)
       )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.borderCard, lineWidth: 1)
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tag.slash")
                .font(.kpiValueSecondary)
                .foregroundStyle(Color.textTertiary)
            Text("Tag your trades in the Journal to build your playbook")
                .font(.smallText)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: 16) {
            summaryItem(
                value: "\(setups.count)",
                label: "SETUPS TRACKED"
            )
            summaryItem(
                value: "\(keepSetups.count)",
                label: "PROFITABLE",
                color: Color.semanticGreen
            )
            summaryItem(
                value: "\(reviewSetups.count)",
                label: "TO REVIEW",
                color: .orange
            )
            summaryItem(
                value: "\(dropSetups.count)",
                label: "TO DROP",
                color: Color.semanticRed
            )
        }
        .padding(12)
        .background(Color.bgContent)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.borderCard, lineWidth: 1)
    )
    }

    private func summaryItem(value: String, label: String, color: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.cardTitle)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.monoSmall)
                .foregroundStyle(Color.textTertiary)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Setup Cards

    private var setupCardsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(setups) { setup in
                setupCard(setup)
            }
        }
    }

    private func setupCard(_ setup: SetupData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: name + classification badge
            HStack {
                Text(setup.name)
                    .font(.smallText)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accent.opacity(0.12))
                    .clipShape(Capsule())

                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: setup.classification.icon)
                        .font(.smallText)
                    Text(setup.classification.rawValue)
                        .font(.smallText)
                        .fontWeight(.bold)
                        .tracking(0.5)
                }
                .foregroundStyle(setup.classification.color)
            }

            // Metrics row
            HStack(spacing: 0) {
                metricColumn("TRADES", value: "\(setup.tradeCount)")
                metricColumn("WIN RATE", value: String(format: "%.0f%%", setup.winRate),
                             color: setup.winRate >= 50 ? Color.semanticGreen : Color.semanticRed)
                metricColumn("AVG R", value: setup.avgR.asRMultiple,
                             color: Color.forPnL(setup.avgR))
                metricColumn("PF", value: setup.profitFactor.asProfitFactor,
                             color: setup.profitFactor >= 1.0 ? Color.semanticGreen : Color.semanticRed)
                metricColumn("TOTAL P&L", value: setup.totalPnL.asCompactCurrency,
                             color: Color.forPnL(setup.totalPnL))
            }

            // Sessions + Sparkline row
            HStack(spacing: 16) {
                // Best/worst session
                VStack(alignment: .leading, spacing: 3) {
                    if let best = setup.bestSession {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.monoSmall)
                                .foregroundStyle(Color.semanticGreen)
                            Text("Best: \(best.displayName)")
                                .font(.smallText)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    if let worst = setup.worstSession, worst != setup.bestSession {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.monoSmall)
                                .foregroundStyle(Color.semanticRed)
                            Text("Worst: \(worst.displayName)")
                                .font(.smallText)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }

                Spacer()

                // P&L sparkline (last 10 trades)
                if !setup.recentPnL.isEmpty {
                    sparkline(data: setup.recentPnL)
                }
            }
        }
        .padding(12)
        .background(Color.bgContent)
        .clipShape(RoundedRectangle(cornerRadius: 12))
       .overlay(
           RoundedRectangle(cornerRadius: 12)
               .stroke(Color.borderCard, lineWidth: 1)
       )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(setup.classification.color.opacity(0.25), lineWidth: 1)
        )
    }

    private func metricColumn(_ label: String, value: String, color: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.monoSubtitle)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.monoSmall)
                .foregroundStyle(Color.textTertiary)
                .tracking(0.3)
        }
        .frame(maxWidth: .infinity)
    }

    /// Mini bar chart showing P&L per trade for the last 10 trades of a setup
    private func sparkline(data: [Double]) -> some View {
        let maxAbs = data.map { abs($0) }.max() ?? 1

        return HStack(spacing: 2) {
            ForEach(Array(data.enumerated()), id: \.offset) { _, pnl in
                let height = max(abs(pnl) / maxAbs * 20, 2)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.forPnL(pnl))
                    .frame(width: 4, height: height)
            }
        }
        .frame(height: 20, alignment: .bottom)
    }

    // MARK: - Ranking Section

    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Text("Keep vs Drop")
                .font(.smallText)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)

            if !keepSetups.isEmpty {
                rankingGroup(
                    title: "Keep",
                    icon: "checkmark.seal.fill",
                    color: Color.semanticGreen,
                    setups: keepSetups
                )
            }

            if !reviewSetups.isEmpty {
                rankingGroup(
                    title: "Review",
                    icon: "exclamationmark.triangle.fill",
                    color: .orange,
                    setups: reviewSetups
                )
            }

            if !dropSetups.isEmpty {
                rankingGroup(
                    title: "Drop",
                    icon: "xmark.seal.fill",
                    color: Color.semanticRed,
                    setups: dropSetups
                )
            }
        }
    }

    private func rankingGroup(title: String, icon: String, color: Color, setups: [SetupData]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.smallText)
                    .foregroundStyle(color)
                Text(title)
                    .font(.smallText)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
            }

            ForEach(setups) { setup in
                HStack {
                    Text(setup.name)
                        .font(.monoSubtitle)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.1))
                        .clipShape(Capsule())

                    Spacer()

                    Text("PF \(setup.profitFactor.asProfitFactor)")
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.textSecondary)

                    Text(setup.totalPnL.asCompactCurrency)
                        .font(.monoSubtitle)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.forPnL(setup.totalPnL))
                        .frame(width: 55, alignment: .trailing)

                    Text("\(setup.tradeCount)t")
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 22, alignment: .trailing)
                }
            }
        }
    }
}
