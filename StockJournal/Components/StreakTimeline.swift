import SwiftUI

/// Visual timeline of consecutive win/loss streaks
struct StreakTimeline: View {
    let trades: [Trade]

    private struct StreakSegment: Identifiable {
        let id = UUID()
        let isWin: Bool
        let count: Int
        let startIndex: Int
    }

    private var segments: [StreakSegment] {
        let sorted = trades.sorted { $0.closeTime < $1.closeTime }
        guard !sorted.isEmpty else { return [] }

        var result: [StreakSegment] = []
        var currentIsWin = sorted[0].isWin
        var currentCount = 1
        var startIdx = 0

        for i in 1..<sorted.count {
            if sorted[i].isWin == currentIsWin {
                currentCount += 1
            } else {
                result.append(StreakSegment(isWin: currentIsWin, count: currentCount, startIndex: startIdx))
                currentIsWin = sorted[i].isWin
                currentCount = 1
                startIdx = i
            }
        }
        result.append(StreakSegment(isWin: currentIsWin, count: currentCount, startIndex: startIdx))
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.semanticGreenDim)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "flame")
                            .font(.smallText)
                            .foregroundStyle(Color.semanticGreen)
                    )
                Text("Streak Timeline")
                    .font(.cardTitle)
            }

            if trades.isEmpty {
                Text("No trades yet")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                // Streak bars
                HStack(spacing: 3) {
                    ForEach(segments) { segment in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(segment.isWin ? Color.semanticGreenDim : Color.semanticRedDim)
                            .frame(width: 18, height: 18)
                            .overlay {
                                if segment.count >= 2 {
                                    Text("\(segment.count)")
                                        .font(.monoSmall).fontWeight(.bold)
                                        .foregroundStyle(segment.isWin ? Color.semanticGreen : Color.semanticRed)
                                }
                            }
                    }
                }

                // Legend
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.semanticGreenDim)
                            .frame(width: 10, height: 10)
                        Text("Win streaks")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.semanticRedDim)
                            .frame(width: 10, height: 10)
                        Text("Loss streaks")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Text("\(segments.count) streaks from \(trades.count) trades")
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)
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
