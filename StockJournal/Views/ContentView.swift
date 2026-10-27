import SwiftUI

struct ContentView: View {
    @Environment(\.appState) private var appState

    // Persist ViewModels across tab switches
    @State private var journalVM: JournalViewModel?
    @State private var dashboardVM: DashboardViewModel?
    @State private var edgeReportVM: EdgeReportViewModel?
    @State private var settingsVM: SettingsViewModel?

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            SidebarView(selectedTab: $appState.selectedTab)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bgContent)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8))
        }
        .navigationSplitViewStyle(.balanced)
        .toast($appState.toast)
        .preferredColorScheme(.dark)
        .onAppear { NSWindow.allowsAutomaticWindowTabbing = false }
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedTab {
        case .journal:
            JournalView(viewModel: getJournalVM())
        case .dashboard:
            DashboardView(viewModel: getDashboardVM(), category: appState.selectedDashboardCategory)
        case .analytics:
            AnalyticsContainerView(viewModel: getDashboardVM())
        case .edgeReport:
            EdgeReportView(viewModel: getEdgeReportVM())
        case .browse:
            TickerLookupView(trades: getJournalVM().trades)
        case .watchlist:
            WatchlistView(trades: getJournalVM().trades)
        case .importTrades:
            let vm = ImportViewModel(
                repository: appState.tradeRepository
            )
            let _ = {
                vm.onImportSuccess = {
                    appState.showToast(.success, "Trades imported successfully")
                    appState.selectedTab = .dashboard
                }
            }()
            ImportView(viewModel: vm)
        case .settings:
            SettingsView(viewModel: getSettingsVM())
        }
    }

    // MARK: - Lazy ViewModel Accessors

    private func getJournalVM() -> JournalViewModel {
        if let vm = journalVM { return vm }
        let vm = JournalViewModel(
            repository: appState.tradeRepository,
            database: appState.database
        )
        DispatchQueue.main.async { journalVM = vm }
        return vm
    }

    private func getDashboardVM() -> DashboardViewModel {
        if let vm = dashboardVM { return vm }
        let vm = DashboardViewModel(
            repository: appState.tradeRepository,
            database: appState.database
        )
        DispatchQueue.main.async { dashboardVM = vm }
        return vm
    }

    private func getEdgeReportVM() -> EdgeReportViewModel {
        if let vm = edgeReportVM { return vm }
        let vm = EdgeReportViewModel(
            repository: appState.tradeRepository,
            database: appState.database
        )
        DispatchQueue.main.async { edgeReportVM = vm }
        return vm
    }

    private func getSettingsVM() -> SettingsViewModel {
        if let vm = settingsVM { return vm }
        let vm = SettingsViewModel(
            repository: appState.tradeRepository,
            appState: appState
        )
        DispatchQueue.main.async { settingsVM = vm }
        return vm
    }
}
