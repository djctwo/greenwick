import SwiftUI

/// Session ranking card showing top sessions by P&L
struct SessionRankingCard: View {
    let trades: [Trade]

    private struct SessionRank: Identifiable {
        let id = UUID()
        let rank: Int
        let name: String
        let pnl: Double
        let trades: Int
        let winRate: Double
    }

    private var sessions: [SessionRank] {
        let grouped = Dictionary(grouping: trades) { $0.session }
        let ranked = MarketSession.allCases.compactMap { session -> (MarketSession, Double, Int, Double)? in
            let sessionTrades = grouped[session] ?? []
            guard !sessionTrades.isEmpty else { return nil }
            let pnl = sessionTrades.reduce(0.0) { $0 + $1.profitDouble }
            let wins = sessionTrades.filter(\.isWin).count
            let wr = Double(wins) / Double(sessionTrades.count) * 100
            return (session, pnl, sessionTrades.count, wr)
        }
        .sorted { $0.1 > $1.1 }

        return ranked.enumerated().map { index, data in
            SessionRank(
                rank: index + 1,
                name: data.0.displayName,
                pnl: data.1,
                trades: data.2,
                winRate: data.3
            )
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Colored left accent bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.semanticAmber.opacity(0.6))
                .frame(width: 3)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.semanticAmber)
                    Text("Session Ranking")
                        .font(.cardTitle)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()

                    Text("\(sessions.count) sessions")
                        .font(.monoSmall)
                        .foregroundStyle(Color.textTertiary)
                }

                // Session list
                if sessions.isEmpty {
                    Text("No trades yet")
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                            HStack(spacing: 12) {
                                // Rank badge
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(session.rank == 1 ? Color.semanticAmberDim : Color.semanticAmber.opacity(0.05))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Text("\(session.rank)")
                                            .font(.monoSubtitle)
                                            .foregroundStyle(session.rank == 1 ? Color.accent : Color.textTertiary)
                                    )

                                // Session name
                                Text(session.name)
                                    .font(.bodyText)
                                    .foregroundStyle(Color.textPrimary)

                                Spacer()

                                // Stats
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(session.pnl.asCurrency)
                                        .font(.bodyText)
                                        .foregroundStyle(Color.forPnL(session.pnl))

                                    Text("\(session.trades)t · \(String(format: "%.1f", session.winRate))%")
                                        .font(.monoSubtitle)
                                        .foregroundStyle(Color.textTertiary)
                                }
                            }
                            .padding(.vertical, 10)

                            if index < sessions.count - 1 {
                                Rectangle()
                                    .fill(Color.borderSubtle)
                                    .frame(height: 1)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session Ranking: \(sessions.map { "\($0.name) \($0.pnl.asCurrency)" }.joined(separator: ", "))")
    }
}
