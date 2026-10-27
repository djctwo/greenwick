import SwiftUI

extension Color {
    // MARK: - Backgrounds (warm charcoal — subtle warm undertone)

    /// App window background — warm near-black (#0c0d0e)
    static let bgApp = Color(red: 0.047, green: 0.051, blue: 0.055)

    /// Sidebar background — slightly warmer (#101214)
    static let bgSidebar = Color(red: 0.063, green: 0.071, blue: 0.078)

    /// Content area background (#0e1012)
    static let bgContent = Color(red: 0.055, green: 0.063, blue: 0.071)

    /// Card surface — warm charcoal (#151718)
    static let bgCard = Color(red: 0.082, green: 0.090, blue: 0.094)

    /// Card surface on hover (#1c1e20)
    static let bgCardHover = Color(red: 0.110, green: 0.118, blue: 0.125)

    /// Inset/nested surface — neutral at low opacity
    static let bgInset = Color(red: 0.500, green: 0.500, blue: 0.510, opacity: 0.04)

    // MARK: - Borders (neutral gray — no teal tint)

    /// Card border — cool gray at 12% opacity
    static let borderCard = Color(red: 0.500, green: 0.520, blue: 0.540, opacity: 0.12)

    /// Subtle divider — cool gray at 7% opacity
    static let borderSubtle = Color(red: 0.500, green: 0.520, blue: 0.540, opacity: 0.07)

    /// Active/focused border — accent at 35% opacity (teal only here)
    static let borderActive = Color(red: 0.0, green: 0.831, blue: 0.667, opacity: 0.35)

    // MARK: - Accent (electric teal)

    /// Primary electric teal accent (#00d4aa)
    static let accent = Color(red: 0.0, green: 0.831, blue: 0.667)

    /// Accent at 10% opacity — for backgrounds of active items
    static let accentDim = Color(red: 0.0, green: 0.831, blue: 0.667, opacity: 0.10)

    /// Gradient end for accent (#00b894)
    static let accentDark = Color(red: 0.0, green: 0.722, blue: 0.580)

    // MARK: - Text (cool off-white)

    /// Primary text — cool off-white (#e0e4e8)
    static let textPrimary = Color(red: 0.878, green: 0.894, blue: 0.910)

    /// Secondary text — cool gray (#7a8490)
    static let textSecondary = Color(red: 0.478, green: 0.518, blue: 0.565)

    /// Tertiary text — dim cool gray (#4a5560)
    static let textTertiary = Color(red: 0.290, green: 0.333, blue: 0.376)

    // MARK: - Semantic Colors

    /// Profit / success green (#5cc98a)
    static let semanticGreen = Color(red: 0.361, green: 0.788, blue: 0.541)

    /// Loss / error red (#e06050)
    static let semanticRed = Color(red: 0.878, green: 0.376, blue: 0.314)

    /// Info / neutral blue (#6ba3d9)
    static let semanticBlue = Color(red: 0.420, green: 0.639, blue: 0.851)

    /// Purple for accents (#a48bd4)
    static let semanticPurple = Color(red: 0.643, green: 0.545, blue: 0.831)

    /// Amber for warnings (#e8b44c)
    static let semanticAmber = Color(red: 0.910, green: 0.706, blue: 0.298)

    /// Cyan for secondary data (#4fb8c4)
    static let semanticCyan = Color(red: 0.310, green: 0.722, blue: 0.769)

    // MARK: - Semantic Dim Variants (badge/tag backgrounds)

    static let semanticGreenDim = Color(red: 0.361, green: 0.788, blue: 0.541, opacity: 0.14)
    static let semanticRedDim = Color(red: 0.878, green: 0.376, blue: 0.314, opacity: 0.14)
    static let semanticBlueDim = Color(red: 0.420, green: 0.639, blue: 0.851, opacity: 0.14)
    static let semanticPurpleDim = Color(red: 0.643, green: 0.545, blue: 0.831, opacity: 0.14)
    static let semanticAmberDim = Color(red: 0.910, green: 0.706, blue: 0.298, opacity: 0.14)
    static let semanticCyanDim = Color(red: 0.310, green: 0.722, blue: 0.769, opacity: 0.14)

    // MARK: - Session Colors

    static let preMarketSession = semanticPurple
    static let regularSession = semanticBlue
    static let afterHoursSession = semanticAmber
    static let extendedSession = Color(red: 0.290, green: 0.333, blue: 0.376)

    // MARK: - Neutral

    /// Breakeven / flat — cool gray
    static let breakeven = Color(red: 0.400, green: 0.440, blue: 0.480)

    // MARK: - Helpers

    /// Color for profit/loss values
    static func forPnL(_ value: Double) -> Color {
        if value > 0 { return .semanticGreen }
        if value < 0 { return .semanticRed }
        return .breakeven
    }

    /// Color for profit/loss Decimal values
    static func forPnL(_ value: Decimal) -> Color {
        forPnL(NSDecimalNumber(decimal: value).doubleValue)
    }

    /// Color for market session
    static func forSession(_ session: MarketSession) -> Color {
        switch session {
        case .preMarket: .preMarketSession
        case .regular: .regularSession
        case .afterHours: .afterHoursSession
        case .extended: .extendedSession
        }
    }

    /// Color for ticker symbol
    static func forTicker(_ symbol: String) -> Color {
        let hash = abs(symbol.hashValue)
        let colors: [Color] = [.semanticBlue, .semanticPurple, .semanticAmber, .semanticCyan, .semanticGreen]
        return colors[hash % colors.count]
    }
}
