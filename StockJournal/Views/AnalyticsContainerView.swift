import SwiftUI

/// Container view that wraps DashboardView with horizontal pill sub-navigation
/// for analytics categories (Timing, Sessions, Symbols, Risk, Behavioral, Advanced)
struct AnalyticsContainerView: View {
    @Bindable var viewModel: DashboardViewModel
    @Environment(\.appState) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedCategory: DashboardViewModel.DashboardCategory = .timing

    /// Analytics-only categories (excludes overview, all, propFirm)
    private let categories: [DashboardViewModel.DashboardCategory] = [
        .timing, .sessions, .symbols, .risk, .behavioral, .advanced
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Pill tab bar
            pillTabBar
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)

            // Content — fade transition on category switch
            DashboardView(viewModel: viewModel, category: selectedCategory)
                .id(selectedCategory)
                .transition(.opacity)
        }
        .navigationTitle("Analytics")
    }

    // MARK: - Pill Tab Bar

    private var pillTabBar: some View {
        HStack(spacing: 6) {
            ForEach(categories) { category in
                pillTab(category)
            }
            Spacer()
        }
    }

    private func pillTab(_ category: DashboardViewModel.DashboardCategory) -> some View {
        let isSelected = selectedCategory == category
        let shortcut = shortcutKey(for: category)

        return Button {
            if reduceMotion {
                selectedCategory = category
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedCategory = category
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: category.icon)
                    .font(.monoSmall)
                Text(category.rawValue)
                    .font(.smallText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.bgApp : Color.textSecondary)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accent : Color.bgCard)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.borderCard, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: .option)
        // `shortcut.character`, not `shortcut`: interpolating a KeyEquivalent prints
        // "KeyEquivalent(character: ...)" in the tooltip and to VoiceOver
        .help(Text(verbatim: "\(category.rawValue) (⌥\(shortcut.character))"))
        .accessibilityLabel(Text(verbatim: "\(category.rawValue), Option \(shortcut.character)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Option+1-6 keyboard shortcuts for analytics sub-tabs
    private func shortcutKey(for category: DashboardViewModel.DashboardCategory) -> KeyEquivalent {
        switch category {
        case .timing: "1"
        case .sessions: "2"
        case .symbols: "3"
        case .risk: "4"
        case .behavioral: "5"
        case .advanced: "6"
        default: "1"
        }
    }
}
