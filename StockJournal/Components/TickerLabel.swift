import SwiftUI

/// Styled ticker label with symbol-specific colors
struct TickerLabel: View {
    let symbol: String

    var body: some View {
        Text(symbol)
            .font(.bodyText)
            .fontWeight(.bold)
            .foregroundStyle(Color.forTicker(symbol))
    }
}

/// Direction pill badge with colored background
struct DirectionLabel: View {
    let direction: TradeDirection

    var body: some View {
        Text(direction.rawValue)
            .font(.monoSubtitle)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(direction == .buy ? Color.semanticGreenDim : Color.semanticRedDim)
            .foregroundStyle(direction == .buy ? Color.semanticGreen : Color.semanticRed)
            .clipShape(Capsule())
    }
}
