import SwiftUI

/// Streak card showing current win/loss streak with recent results
struct StreakCard: View {
    let trades: [Trade]

    private var sortedTrades: [Trade] {
        trades.sorted { $0.closeTime < $1.closeTime }
    }

    private var currentStreak: Int {
        guard let last = sortedTrades.last else { return 0 }
        let isWin = last.isWin
        var count = 0
        for trade in sortedTrades.reversed() {
            if trade.isWin == isWin {
                count += 1
            } else {
                break
            }
        }
        return isWin ? count : -count
    }

    private var bestWinStreak: Int {
        var best = 0
        var current = 0
        for trade in sortedTrades {
            if trade.isWin {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    private var bestLossStreak: Int {
        var best = 0
        var current = 0
        for trade in sortedTrades {
            if trade.isLoss {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    /// Last 10 trade results (most recent last)
    private var recentResults: [Bool] {
        sortedTrades.suffix(10).map(\.isWin)
    }

    /// True when current win streak is at or near the personal best (≥80% of best, minimum 3)
    private var isNearPersonalBest: Bool {
        guard currentStreak >= 3, bestWinStreak >= 3 else { return false }
        return currentStreak >= Int(ceil(Double(bestWinStreak) * 0.8))
    }

    var body: some View {
        HStack(spacing: 0) {
            // Colored left accent bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill((currentStreak >= 0 ? Color.semanticGreen : Color.semanticRed).opacity(0.6))
                .frame(width: 3)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.monoSubtitle)
                        .foregroundStyle(currentStreak >= 0 ? Color.semanticGreen : Color.semanticRed)
                    Text("Streak")
                        .font(.cardTitle)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()

                    // Streak badge
                    if !trades.isEmpty {
                        let streakText = currentStreak >= 0 ? "+\(currentStreak)" : "\(currentStreak)"
                        let streakColor = currentStreak >= 0 ? Color.semanticGreen : Color.semanticRed
                        let streakBg = currentStreak >= 0 ? Color.semanticGreenDim : Color.semanticRedDim
                        Text(streakText)
                            .font(.monoSubtitle)
                            .foregroundStyle(streakColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(streakBg)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                if trades.isEmpty {
                    Text("No trades yet")
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    // Big streak number
                    VStack(spacing: 8) {
                        Text(currentStreak >= 0 ? "+\(currentStreak)" : "\(currentStreak)")
                            .font(.kpiValue)
                            .foregroundStyle(currentStreak >= 0 ? Color.semanticGreen : Color.semanticRed)

                        if isNearPersonalBest {
                            Text(currentStreak == bestWinStreak ? "Personal Best!" : "Near Personal Best!")
                                .font(.monoSmall)
                                .foregroundStyle(Color.semanticAmber)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.semanticAmberDim)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        Text("Best: \(bestWinStreak)W / \(bestLossStreak)L")
                            .font(.sidebarItem)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)

                    // Win/loss timeline
                    VStack(spacing: 4) {
                        Text("Last \(recentResults.count)")
                            .font(.monoSmall)
                            .foregroundStyle(Color.textTertiary)
                        HStack(spacing: 3) {
                            Spacer()
                            ForEach(Array(recentResults.enumerated()), id: \.offset) { index, isWin in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isWin ? Color.semanticGreenDim : Color.semanticRedDim)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Text(isWin ? "W" : "L")
                                            .font(.monoSmall)
                                            .foregroundStyle(isWin ? Color.semanticGreen : Color.semanticRed)
                                    )
                                    .accessibilityLabel("Trade \(index + 1): \(isWin ? "Win" : "Loss")")
                            }
                            Spacer()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Recent results: \(recentResults.filter { $0 }.count) wins, \(recentResults.filter { !$0 }.count) losses")
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
    }
}
