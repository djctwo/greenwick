import SwiftUI

/// Visual indicator showing an up/down/flat trend with percentage change
struct TrendIndicator: View {
    let current: Double
    let previous: Double

    private var changePercent: Double {
        guard previous != 0 else { return 0 }
        return ((current - previous) / abs(previous)) * 100
    }

    private var trend: Trend {
        if changePercent > 1 { return .up }
        if changePercent < -1 { return .down }
        return .flat
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: trend.icon)
                .font(.smallText)
            Text(String(format: "%.1f%%", abs(changePercent)))
                .font(.monoSubtitle)
        }
        .foregroundStyle(trend.color)
    }

    private enum Trend {
        case up, down, flat

        var icon: String {
            switch self {
            case .up: "arrow.up.right"
            case .down: "arrow.down.right"
            case .flat: "arrow.right"
            }
        }

        var color: Color {
            switch self {
            case .up: .semanticGreen
            case .down: .semanticRed
            case .flat: .secondary
            }
        }
    }
}
