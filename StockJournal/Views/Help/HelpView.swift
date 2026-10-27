import SwiftUI

/// Comprehensive in-app help system with sidebar navigation
struct HelpView: View {
    @State private var selectedTopic: HelpTopic = .gettingStarted
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTopic) {
                Section("Basics") {
                    topicRow(.gettingStarted)
                    topicRow(.importingTrades)
                    topicRow(.exportingData)
                }
                Section("Features") {
                    topicRow(.journal)
                    topicRow(.dashboard)
                    topicRow(.edgeReport)
                    topicRow(.tradeReplay)
                }
                Section("Analytics Guide") {
                    topicRow(.metricsExplained)
                    topicRow(.analyticsComponents)
                    topicRow(.aiAnalysis)
                }
                Section("Platform Import Guides") {
                    topicRow(.importThinkorswim)
                    topicRow(.importInteractiveBrokers)
                    topicRow(.importWebull)
                    topicRow(.importTradingView)
                    topicRow(.importNinjaTrader)
                    topicRow(.importGenericCSV)
                }
                Section("Settings & Security") {
                    topicRow(.settings)
                    topicRow(.appLock)
                    topicRow(.keyboardShortcuts)
                }
                Section("Reference") {
                    topicRow(.glossary)
                    topicRow(.faq)
                    topicRow(.troubleshooting)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
            .searchable(text: $searchText, prompt: "Search help")
        } detail: {
            ScrollView {
                selectedTopic.content
                    .padding(32)
                    .frame(maxWidth: 720, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .background(Color.bgContent)
        }
        .frame(minWidth: 800, minHeight: 550)
    }

    private func topicRow(_ topic: HelpTopic) -> some View {
        Label(topic.title, systemImage: topic.icon)
            .tag(topic)
    }
}

// MARK: - Help Topics

enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted, importingTrades, exportingData
    case journal, dashboard, edgeReport, tradeReplay
    case metricsExplained, analyticsComponents, aiAnalysis
    case importThinkorswim, importInteractiveBrokers, importWebull
    case importTradingView, importNinjaTrader, importGenericCSV
    case settings, appLock, keyboardShortcuts
    case glossary, faq, troubleshooting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: "Getting Started"
        case .importingTrades: "Importing Trades"
        case .exportingData: "Exporting Data"
        case .journal: "Trade Journal"
        case .dashboard: "Dashboard"
        case .edgeReport: "Edge Report"
        case .tradeReplay: "Trade Replay"
        case .metricsExplained: "Metrics Explained"
        case .analyticsComponents: "Analytics Components"
        case .aiAnalysis: "AI Analysis"
        case .importThinkorswim: "Thinkorswim"
        case .importInteractiveBrokers: "Interactive Brokers"
        case .importWebull: "Webull"
        case .importTradingView: "TradingView"
        case .importNinjaTrader: "NinjaTrader"
        case .importGenericCSV: "Generic CSV"
        case .settings: "Settings"
        case .appLock: "App Lock"
        case .keyboardShortcuts: "Keyboard Shortcuts"
        case .glossary: "Glossary"
        case .faq: "FAQ"
        case .troubleshooting: "Troubleshooting"
        }
    }

    var icon: String {
        switch self {
        case .gettingStarted: "star"
        case .importingTrades: "square.and.arrow.down"
        case .exportingData: "square.and.arrow.up"
        case .journal: "list.bullet.rectangle"
        case .dashboard: "chart.bar.xaxis"
        case .edgeReport: "target"
        case .tradeReplay: "play.rectangle"
        case .metricsExplained: "function"
        case .analyticsComponents: "chart.dots.scatter"
        case .aiAnalysis: "brain"
        case .importThinkorswim: "arrow.down.doc"
        case .importInteractiveBrokers: "arrow.down.doc"
        case .importWebull: "arrow.down.doc"
        case .importTradingView: "arrow.down.doc"
        case .importNinjaTrader: "arrow.down.doc"
        case .importGenericCSV: "arrow.down.doc"
        case .settings: "gearshape"
        case .appLock: "lock.shield"
        case .keyboardShortcuts: "keyboard"
        case .glossary: "book"
        case .faq: "questionmark.circle"
        case .troubleshooting: "wrench.and.screwdriver"
        }
    }

    @ViewBuilder
    var content: some View {
        switch self {
        case .gettingStarted: HelpGettingStarted()
        case .importingTrades: HelpImportingTrades()
        case .exportingData: HelpExportingData()
        case .journal: HelpJournal()
        case .dashboard: HelpDashboard()
        case .edgeReport: HelpEdgeReport()
        case .tradeReplay: HelpTradeReplay()
        case .metricsExplained: HelpMetrics()
        case .analyticsComponents: HelpAnalyticsComponents()
        case .aiAnalysis: HelpAIAnalysis()
        case .importThinkorswim: HelpImportThinkorswim()
        case .importInteractiveBrokers: HelpImportIB()
        case .importWebull: HelpImportWebull()
        case .importTradingView: HelpImportTradingView()
        case .importNinjaTrader: HelpImportNinjaTrader()
        case .importGenericCSV: HelpImportGenericCSV()
        case .settings: HelpSettings()
        case .appLock: HelpAppLock()
        case .keyboardShortcuts: HelpKeyboardShortcuts()
        case .glossary: HelpGlossary()
        case .faq: HelpFAQ()
        case .troubleshooting: HelpTroubleshooting()
        }
    }
}
