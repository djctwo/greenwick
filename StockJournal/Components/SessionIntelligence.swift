import SwiftUI

/// Provides session-level intelligence: which sessions to focus on and avoid
struct SessionIntelligence: View {
    let trades: [Trade]

    private struct SessionData: Identifiable {
        let id: String
        let session: MarketSession
        let profit: Double
        let tradeCount: Int
        let winRate: Double
        let avgR: Double
        let profitFactor: Double
        let recommendation: Recommendation

        enum Recommendation {
            case focus, neutral, reduce, avoid

            var label: String {
                switch self {
                case .focus: "FOCUS"
                case .neutral: "OK"
                case .reduce: "REDUCE"
                case .avoid: "AVOID"
                }
            }

            var color: Color {
                switch self {
                case .focus: Color.semanticGreen
                case .neutral: .secondary
                case .reduce: .orange
                case .avoid: Color.semanticRed
                }
            }

            var icon: String {
                switch self {
                case .focus: "star.fill"
                case .neutral: "minus.circle"
                case .reduce: "arrow.down.circle"
                case .avoid: "xmark.circle.fill"
                }
            }
        }
    }

    private var sessionData: [SessionData] {
        let grouped = Dictionary(grouping: trades) { $0.session }
        return MarketSession.allCases.compactMap { session in
            let sessionTrades = grouped[session] ?? []
            guard !sessionTrades.isEmpty else { return nil }
            let profit = sessionTrades.reduce(0.0) { $0 + $1.profitDouble }
            let wins = sessionTrades.filter(\.isWin).count
            let wr = Double(wins) / Double(sessionTrades.count) * 100
            let avgR = sessionTrades.map(\.rMultiple).reduce(0, +) / Double(sessionTrades.count)
            let grossWin = sessionTrades.filter(\.isWin).map(\.profitDouble).reduce(0, +)
            let grossLoss = abs(sessionTrades.filter(\.isLoss).map(\.profitDouble).reduce(0, +))
            let pf = grossLoss > 0 ? grossWin / grossLoss : grossWin > 0 ? .infinity : 0

            // Recommendation logic
            let rec: SessionData.Recommendation
            if avgR >= 0.5 && wr >= 50 && sessionTrades.count >= 5 {
                rec = .focus
            } else if avgR >= 0 && wr >= 40 {
                rec = .neutral
            } else if avgR < 0 && sessionTrades.count >= 5 {
                rec = .avoid
            } else {
                rec = .reduce
            }

            return SessionData(
                id: session.rawValue,
                session: session,
                profit: profit,
                tradeCount: sessionTrades.count,
                winRate: wr,
                avgR: avgR,
                profitFactor: pf,
                recommendation: rec
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.semanticAmberDim)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "brain.head.profile")
                            .font(.smallText)
                            .foregroundStyle(Color.accent)
                    )
                Text("Session Intelligence")
                    .font(.cardTitle)
            }

            if sessionData.isEmpty {
                Text("No trades yet")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ForEach(sessionData) { data in
                    HStack(spacing: 8) {
                        // Recommendation badge
                        HStack(spacing: 3) {
                            Image(systemName: data.recommendation.icon)
                                .font(.monoSmall)
                            Text(data.recommendation.label)
                                .font(.monoSmall).fontWeight(.bold)
                        }
                        .foregroundStyle(data.recommendation.color)
                        .frame(width: 65)

                        // Session name
                        Text(data.session.displayName)
                            .font(.smallText)
                            .fontWeight(.medium)
                            .frame(width: 70, alignment: .leading)

                        // Stats
                        Text(data.profit.asCompactCurrency)
                            .font(.monoSubtitle)
                            .foregroundStyle(Color.forPnL(data.profit))
                            .frame(width: 50, alignment: .trailing)

                        Text(String(format: "%.0f%%", data.winRate))
                            .font(.monoSubtitle)
                            .frame(width: 32, alignment: .trailing)

                        Text(data.avgR.asRMultiple)
                            .font(.monoSubtitle)
                            .foregroundStyle(Color.forPnL(data.avgR))
                            .frame(width: 40, alignment: .trailing)

                        ConfidenceBadge(sampleSize: data.tradeCount, compact: true)
                            .frame(width: 14, alignment: .trailing)

                        Text("\(data.tradeCount)t")
                            .font(.smallText)
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 25, alignment: .trailing)
                    }

                    if data.id != sessionData.last?.id {
                        Divider()
                    }
                }

                // Overall recommendation
                let focusSessions = sessionData.filter { $0.recommendation == .focus }
                let avoidSessions = sessionData.filter { $0.recommendation == .avoid }

                if !focusSessions.isEmpty || !avoidSessions.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        if !focusSessions.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.smallText)
                                    .foregroundStyle(Color.semanticGreen)
                                Text("Focus on: \(focusSessions.map { $0.session.displayName }.joined(separator: ", "))")
                                    .font(.smallText)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        if !avoidSessions.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.smallText)
                                    .foregroundStyle(Color.semanticRed)
                                Text("Avoid: \(avoidSessions.map { $0.session.displayName }.joined(separator: ", "))")
                                    .font(.smallText)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
    }
}
