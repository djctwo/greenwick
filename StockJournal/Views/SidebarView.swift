import SwiftUI

struct SidebarView: View {
    @Binding var selectedTab: SidebarTab
    @Environment(\.appState) private var appState
    @State private var marketExpanded = true
    @State private var toolsExpanded = true
    @State private var hoveredTab: SidebarTab?

    var body: some View {
        VStack(spacing: 0) {
            // Logo
            logoHeader
                .padding(.top, 12)
                .padding(.bottom, 12)

            // Navigation
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SidebarTab.tabs(for: .core)) { tab in
                        sidebarRow(tab)
                    }

                    sectionHeader("MARKET", isExpanded: $marketExpanded)
                    if marketExpanded {
                        ForEach(SidebarTab.tabs(for: .market)) { tab in
                            sidebarRow(tab)
                        }
                    }

                    sectionHeader("TOOLS", isExpanded: $toolsExpanded)
                    if toolsExpanded {
                        ForEach(SidebarTab.tabs(for: .tools)) { tab in
                            sidebarRow(tab)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()

            // Bottom area — isolated timer scope
            SessionClockWidget()
        }
        .background(Color.bgSidebar)
    }

    // MARK: - Logo Header

    private var logoHeader: some View {
        HStack(spacing: 8) {
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            Text("Greenwick")
                .font(.logoText)
                .foregroundStyle(Color.textPrimary)

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Navigation Row

    private func sidebarRow(_ tab: SidebarTab) -> some View {
        let isSelected = selectedTab == tab
        let isHovered = hoveredTab == tab

        return Button {
            if tab == .dashboard {
                appState.selectedDashboardCategory = .overview
            }
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(isSelected ? Color.accent : isHovered ? Color.accent.opacity(0.6) : Color.textTertiary)

                Text(tab.rawValue)
                    .font(.sidebarItem)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.accent : isHovered ? Color.textPrimary : Color.textSecondary)

                Spacer()

                if isHovered, let hint = tab.shortcutHint {
                    Text(hint)
                        .font(.monoSmall)
                        .foregroundStyle(Color.textTertiary.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected ? Color.accent.opacity(0.12) :
                        isHovered ? Color.accent.opacity(0.04) :
                        Color.clear
                    )
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accent)
                        .frame(width: 3, height: 18)
                        .offset(x: 0)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accent.opacity(0.15) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.\(tab.rawValue)")
        .onHover { hovering in
            hoveredTab = hovering ? tab : nil
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, isExpanded: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.borderSubtle)
                .frame(height: 1)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.sectionLabel)
                        .fontWeight(.semibold)
                        .tracking(1.2)
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.monoSmall)
                        .foregroundStyle(Color.textTertiary)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            .buttonStyle(.plain)
        }
    }

}

// MARK: - Session Clock Widget (isolated timer — prevents sidebar redraws)

/// Extracted to its own view so the 1-second timer only redraws the clock, not the entire sidebar
struct SessionClockWidget: View {
    @State private var currentTime = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let etFormatter: DateFormatter = TradingCalendar.formatter("HH:mm:ss")

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.borderSubtle)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.forSession(currentTime.marketSession))
                        .frame(width: 8, height: 8)

                    Text(currentTime.marketSession.displayName)
                        .font(.sidebarItem)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.textPrimary)

                    Spacer()

                    Text(Self.etFormatter.string(from: currentTime))
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                }

                HStack {
                    Text(timeRemainingText)
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text("ET")
                        .font(.monoSmall)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onReceive(timer) { time in
            currentTime = time
        }
    }

    private var timeRemainingText: String {
        let remaining = currentTime.timeToNextSession
        let seconds = Int(saturating: remaining)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let time = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"

        switch currentTime.marketSession {
        case .preMarket: return "\(time) to open"
        case .regular: return "\(time) to close"
        case .afterHours: return "\(time) to AH close"
        case .extended: return "\(time) to pre-market"
        }
    }
}
