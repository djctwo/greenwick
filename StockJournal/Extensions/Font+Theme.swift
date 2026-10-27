import SwiftUI

extension Font {
    // MARK: - KPI / Metrics

    /// Large KPI value — JetBrains Mono 28pt bold (tracking: -1px at view level)
    static let kpiValue = Font.custom("JetBrains Mono", size: 28).weight(.bold)

    /// Secondary KPI value — JetBrains Mono 22pt bold
    static let kpiValueSecondary = Font.custom("JetBrains Mono", size: 22).weight(.bold)

    /// KPI label — DM Sans 14pt semibold (tracking: 0.8px, uppercase at view level)
    static let kpiLabel = Font.custom("DM Sans", size: 14).weight(.semibold)

    // MARK: - Cards & Sections

    /// Card title — DM Sans 17pt semibold
    static let cardTitle = Font.custom("DM Sans", size: 17).weight(.semibold)

    /// Section header label — DM Sans 13pt semibold (tracking: 1.2px, uppercase at view level)
    static let sectionLabel = Font.custom("DM Sans", size: 13).weight(.semibold)

    /// Table column header — DM Sans 14pt semibold (tracking: 0.6px, uppercase at view level)
    static let tableHeader = Font.custom("DM Sans", size: 14).weight(.semibold)

    /// Table cell value — JetBrains Mono 15pt
    static let tableCell = Font.custom("JetBrains Mono", size: 15)

    // MARK: - Body Text

    /// Body text — DM Sans 16pt medium
    static let bodyText = Font.custom("DM Sans", size: 16).weight(.medium)

    /// Small supporting text — DM Sans 13pt medium (replaces .caption on text)
    static let smallText = Font.custom("DM Sans", size: 13).weight(.medium)

    /// Small mono text — JetBrains Mono 14pt
    static let monoSubtitle = Font.custom("JetBrains Mono", size: 14)

    /// Small mono for annotations — JetBrains Mono 11pt
    static let monoSmall = Font.custom("JetBrains Mono", size: 11)

    // MARK: - Pulse / Session

    /// Session clock display — JetBrains Mono 32pt bold (tracking: -1px at view level)
    static let sessionClock = Font.custom("JetBrains Mono", size: 32).weight(.bold)

    /// Session name display — DM Sans 28pt bold (tracking: -0.5px at view level)
    static let sessionName = Font.custom("DM Sans", size: 28).weight(.bold)

    // MARK: - Sidebar

    /// Sidebar item label — DM Sans 15pt medium
    static let sidebarItem = Font.custom("DM Sans", size: 15).weight(.medium)

    /// Sidebar section header — DM Sans 13pt semibold (tracking: 1.2px, uppercase at view level)
    static let sidebarSection = sectionLabel

    /// Logo text — DM Sans 18pt bold
    static let logoText = Font.custom("DM Sans", size: 18).weight(.bold)
}
