import SwiftUI

/// Strategy version control — mark changes and see before/after comparison
struct StrategyCheckpoints: View {
    let trades: [Trade]
    let checkpoints: [StrategyCheckpoint]
    var onAdd: ((StrategyCheckpoint) -> Void)?
    var onDelete: ((Int64) -> Void)?

    @State private var showingAddSheet = false

    // MARK: - Comparison Data

    private struct ComparisonMetrics {
        let tradeCount: Int
        let winRate: Double
        let profitFactor: Double
        let expectancy: Double
        let avgR: Double
        let maxDrawdown: Double
        let sharpe: Double
    }

    private func metrics(for filtered: [Trade]) -> ComparisonMetrics {
        guard !filtered.isEmpty else {
            return ComparisonMetrics(tradeCount: 0, winRate: 0, profitFactor: 0, expectancy: 0, avgR: 0, maxDrawdown: 0, sharpe: 0)
        }
        let m = MetricsCalculator.calculate(from: filtered)
        return ComparisonMetrics(
            tradeCount: m.totalTrades,
            winRate: m.winRate,
            profitFactor: m.profitFactor,
            expectancy: m.expectancy,
            avgR: m.averageRMultiple,
            maxDrawdown: m.maxDrawdown,
            sharpe: m.sharpeRatio
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Strategy Checkpoints", systemImage: "flag.fill")
                    .font(.cardTitle)
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus.circle")
                        .font(.smallText)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            if checkpoints.isEmpty {
                VStack(spacing: 8) {
                    Text("No checkpoints yet")
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)
                    Text("Mark strategy changes to track their impact over time")
                        .font(.smallText)
                        .foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ForEach(checkpoints) { checkpoint in
                    checkpointCard(checkpoint)
                    if checkpoint.id != checkpoints.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
        .sheet(isPresented: $showingAddSheet) {
            AddCheckpointSheet(onSave: { checkpoint in
                onAdd?(checkpoint)
            })
        }
    }

    // MARK: - Checkpoint Card

    private func checkpointCard(_ checkpoint: StrategyCheckpoint) -> some View {
        let before = trades.filter { $0.closeTime < checkpoint.date }.sorted { $0.closeTime < $1.closeTime }
        let after = trades.filter { $0.closeTime >= checkpoint.date }.sorted { $0.closeTime < $1.closeTime }
        let beforeMetrics = metrics(for: before)
        let afterMetrics = metrics(for: after)

        return VStack(alignment: .leading, spacing: 8) {
            // Title row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(checkpoint.title)
                        .font(.smallText)
                        .fontWeight(.semibold)
                    Text(checkpoint.date.formatted(.dateTime.month().day().year()))
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                if let id = checkpoint.id {
                    Button {
                        onDelete?(id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !checkpoint.description.isEmpty {
                Text(checkpoint.description)
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }

            // Before/After comparison
            if beforeMetrics.tradeCount >= 5 && afterMetrics.tradeCount >= 5 {
                HStack(spacing: 16) {
                    comparisonColumn("Before", beforeMetrics)
                    Divider().frame(height: 80)
                    comparisonColumn("After", afterMetrics)
                }

                // Confidence note
                HStack(spacing: 4) {
                    ConfidenceBadge(sampleSize: min(beforeMetrics.tradeCount, afterMetrics.tradeCount))
                    Text("for comparison")
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)
                }
            } else {
                Text("Need 5+ trades on each side for comparison")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    private func comparisonColumn(_ label: String, _ m: ComparisonMetrics) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.smallText)
                .fontWeight(.bold)
                .foregroundStyle(Color.textSecondary)
            metricRow("WR", String(format: "%.1f%%", m.winRate))
            metricRow("PF", String(format: "%.2f", m.profitFactor))
            metricRow("Exp", m.expectancy.asCurrency)
            metricRow("Avg R", String(format: "%.2f", m.avgR))
            metricRow("Sharpe", String(format: "%.2f", m.sharpe))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.monoSubtitle)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 45, alignment: .leading)
            Text(value)
                .font(.monoSubtitle)
        }
    }
}

// MARK: - Add Checkpoint Sheet

private struct AddCheckpointSheet: View {
    let onSave: (StrategyCheckpoint) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var date = Date()

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Strategy Checkpoint")
                .font(.cardTitle)

            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("What changed?", text: $title)
                    .textFieldStyle(.roundedBorder)
                TextField("Details (optional)", text: $description, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let checkpoint = StrategyCheckpoint(date: date, title: title, description: description)
                    onSave(checkpoint)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 400, height: 300)
    }
}
