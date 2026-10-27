import Foundation

enum SidebarTab: String, CaseIterable, Identifiable {
    // Core
    case journal = "Journal"
    case dashboard = "Dashboard"
    case analytics = "Analytics"
    // Market
    case browse = "Browse"
    case watchlist = "Watchlist"
    // Tools
    case edgeReport = "Edge Report"
    case importTrades = "Import"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .journal: "list.bullet.rectangle"
        case .dashboard: "chart.bar.xaxis"
        case .analytics: "chart.xyaxis.line"
        case .browse: "magnifyingglass"
        case .watchlist: "star"
        case .edgeReport: "target"
        case .importTrades: "square.and.arrow.down"
        case .settings: "gearshape"
        }
    }

    /// Keyboard shortcut hint displayed in sidebar (nil if no shortcut)
    var shortcutHint: String? {
        switch self {
        case .journal: "⌘1"
        case .dashboard: "⌘2"
        case .analytics: "⌘3"
        case .edgeReport: "⌘4"
        case .importTrades: "⌘5"
        case .settings: "⌘,"
        case .browse: nil
        case .watchlist: nil
        }
    }

    /// Sidebar section grouping
    enum Section: String, CaseIterable {
        case core = "Core"
        case market = "Market"
        case tools = "Tools"
    }

    var section: Section {
        switch self {
        case .journal, .dashboard, .analytics: .core
        case .browse, .watchlist: .market
        case .edgeReport, .importTrades, .settings: .tools
        }
    }

    /// Tabs for each section, in display order
    static func tabs(for section: Section) -> [SidebarTab] {
        allCases.filter { $0.section == section }
    }
}

// MARK: - App Notifications

extension Notification.Name {
    /// Posted when Cmd+N triggers "New Trade" from the menu bar
    static let showAddTrade = Notification.Name("showAddTrade")
}
