import SwiftUI
import Charts
import AppKit

struct EdgeReportView: View {
    @Bindable var viewModel: EdgeReportViewModel
    @Environment(\.appState) private var appState

    var body: some View {
        ScrollView {
            if !viewModel.hasEnoughData {
                insufficientDataView
            } else {
                VStack(spacing: 24) {
                    headerSummary
                    aiAnalysisSection
                    edgeSections
                    TagAnalytics(trades: viewModel.trades)
                }
                .padding(16)
            }
        }
        .navigationTitle("Edge Report")
        .toolbar {
            if viewModel.hasEnoughData {
                ToolbarItem {
                    Button {
                        exportEdgeReportPDF()
                    } label: {
                        Label("Export PDF", systemImage: "square.and.arrow.up")
                            .font(.smallText)
                    }
                }
            }
        }
    }

    // MARK: - Export

    private func exportEdgeReportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Greenwick_EdgeReport_\(Date().formatted(.dateTime.year().month().day())).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let trades = viewModel.trades
        let metrics = viewModel.metrics
        let exporter = PDFExporter()
        do {
            try exporter.exportEdgeReport(
                trades: trades,
                metrics: metrics,
                edgeBySession: MetricsCalculator.edgeBySession(from: trades),
                edgeByHour: MetricsCalculator.edgeByHour(from: trades),
                edgeBySymbol: MetricsCalculator.edgeBySymbol(from: trades),
                edgeByDay: MetricsCalculator.edgeByDay(from: trades),
                to: url
            )
            appState.showToast(.success, "Edge Report exported to PDF")
        } catch {
            appState.showToast(.error, "Export failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Insufficient Data

    private var insufficientDataView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.kpiValue)
                .foregroundStyle(Color.textTertiary)
            Text("Need More Data")
                .font(.kpiValueSecondary)
                .fontWeight(.medium)
            Text("Import at least \(Configuration.minimumTradesForAnalysis) trades to generate your edge report.")
                .font(.bodyText)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Text("\(viewModel.trades.count) / \(Configuration.minimumTradesForAnalysis) trades imported")
                .font(.smallText)
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Header Summary

    private var headerSummary: some View {
        HStack(spacing: 16) {
            MetricCard(
                title: "Total P&L",
                value: viewModel.metrics.totalProfit.asCurrency,
                subtitle: "\(viewModel.metrics.totalTrades) trades analyzed",
                valueColor: Color.forPnL(viewModel.metrics.totalProfit),
                icon: "dollarsign.circle"
            )
            MetricCard(
                title: "Win Rate",
                value: viewModel.metrics.winRate.asPercent,
                subtitle: "\(viewModel.metrics.wins)W / \(viewModel.metrics.losses)L",
                valueColor: viewModel.metrics.winRate >= 50 ? .semanticGreen : .semanticRed,
                icon: "target"
            )
            MetricCard(
                title: "Profit Factor",
                value: viewModel.metrics.profitFactor.asProfitFactor,
                valueColor: viewModel.metrics.profitFactor >= 1 ? .semanticGreen : .semanticRed,
                icon: "chart.bar"
            )
            MetricCard(
                title: "Expectancy",
                value: viewModel.metrics.expectancy.asCurrency,
                subtitle: "per trade",
                valueColor: Color.forPnL(viewModel.metrics.expectancy),
                icon: "function"
            )
        }
    }

    // MARK: - AI Analysis

    @ViewBuilder
    private var aiAnalysisSection: some View {
        let hasContent = viewModel.aiRecommendations != nil || viewModel.aiError != nil || viewModel.isAnalyzing

        if hasContent {
            // Expanded card with results
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("AI Recommendations", systemImage: "brain")
                        .font(.cardTitle)
                    Spacer()
                    if viewModel.isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                        Text("Analyzing...")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        Button {
                            Task { await viewModel.runAIAnalysis() }
                        } label: {
                            Label("Re-run", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)
                    }
                }

                if let error = viewModel.aiError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(error)
                            .font(.smallText)
                            .foregroundStyle(Color.semanticRed)
                    }
                    .padding(8)
                    .background(Color.semanticRed.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.borderCard, lineWidth: 1)
                    )
                }

                if let recommendations = viewModel.aiRecommendations {
                    Text(recommendations)
                        .font(.bodyText)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(Color.bgContent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.borderCard, lineWidth: 1)
                        )
                }
            }
            .padding(16)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderCard, lineWidth: 1)
            )
        } else {
            // Compact action bar — no results yet
            let isReady = Configuration.AI.isReady
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("AI Recommendations (optional)", systemImage: "brain")
                        .font(.cardTitle)
                    Spacer()
                    if isReady {
                        Button {
                            Task { await viewModel.runAIAnalysis() }
                        } label: {
                            Label("Run Analysis", systemImage: "play.fill")
                        }
                        .controlSize(.small)
                        .disabled(!viewModel.hasEnoughData)
                    } else {
                        Button {
                            appState.selectedTab = .settings
                        } label: {
                            Label("Open Settings", systemImage: "gearshape")
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("edgeReport.openAISettings")
                    }
                }
                Text(isReady
                     ? Configuration.AI.dataSentDescription
                     : "Add your own Anthropic API key and switch on AI analysis in Settings > AI Analysis to get written recommendations. Everything else on this page works without it.")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderCard, lineWidth: 1)
            )
        }
    }

    // MARK: - Edge Sections

    private var edgeSections: some View {
        VStack(spacing: 20) {
            edgeSection(
                title: "By Session",
                icon: "clock",
                sectionColor: .semanticBlue,
                makers: viewModel.topMakersBySession,
                losers: viewModel.topLosersBySession
            )

            edgeSection(
                title: "By Hour",
                icon: "clock.badge",
                sectionColor: .semanticAmber,
                makers: viewModel.topMakersByHour,
                losers: viewModel.topLosersByHour
            )

            edgeSection(
                title: "By Symbol",
                icon: "arrow.left.arrow.right",
                sectionColor: .semanticPurple,
                makers: viewModel.topMakersBySymbol,
                losers: viewModel.topLosersBySymbol
            )

            edgeSection(
                title: "By Day of Week",
                icon: "calendar",
                sectionColor: .semanticCyan,
                makers: viewModel.topMakersByDay,
                losers: viewModel.topLosersByDay
            )
        }
    }

    private func edgeSection(
        title: String,
        icon: String,
        sectionColor: Color = .textPrimary,
        makers: [MetricsCalculator.EdgeBreakdown],
        losers: [MetricsCalculator.EdgeBreakdown]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.cardTitle)
                .foregroundStyle(sectionColor)

            HStack(alignment: .top, spacing: 16) {
                edgeColumn(
                    heading: "Where You Make Money",
                    items: makers,
                    accentColor: .semanticGreen
                )
                edgeColumn(
                    heading: "Where You Lose Money",
                    items: losers,
                    accentColor: .semanticRed
                )
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

    private func edgeColumn(
        heading: String,
        items: [MetricsCalculator.EdgeBreakdown],
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading)
                .font(.smallText)
                .fontWeight(.medium)
                .foregroundStyle(accentColor)

            if items.isEmpty {
                Text("None")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        Text("#\(index + 1)")
                            .font(.smallText)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 22)
                        Text(item.label)
                            .font(.monoSubtitle)
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(item.profit.asCurrency)
                                .font(.monoSubtitle)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.forPnL(item.profit))
                            Text("\(item.tradeCount)t · \(item.winRate.asPercent)")
                                .font(.smallText)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding(.vertical, 2)
                    if index < items.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}
