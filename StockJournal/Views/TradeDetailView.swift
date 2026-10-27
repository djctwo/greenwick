import SwiftUI
import os

/// Detail sheet showing all info about a single trade
struct TradeDetailView: View {
    private static let logger = Logger(subsystem: "com.greenwick", category: "TradeDetail")

    let trade: Trade
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appState) private var appState
    @State private var tradeNotes: String = ""
    @State private var tradeTags: String = ""
    @State private var newTag: String = ""
    @State private var selectedEmotion: String = ""
    @State private var commissionText: String = "0"
    @State private var swapText: String = "0"
    @State private var checklistResults: [String: Bool] = [:]
    @State private var notesSaveTask: Task<Void, Never>?
    @State private var costsSaveTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 16) {
                    coreDetails
                    priceDetails
                    metricsSection
                    costsSection
                    emotionSection
                    advancedMetrics
                    checklistSection
                    screenshotsSection
                    tagsSection
                    notesSection
                    metadataSection
                }
                .padding(16)
            }
        }
        .frame(width: 520, height: 700)
        .onAppear {
            tradeNotes = trade.notes
            tradeTags = trade.tags
            selectedEmotion = trade.emotion
            commissionText = trade.commission == 0 ? "" : "\(trade.commission)"
            swapText = trade.swap == 0 ? "" : "\(trade.swap)"
            checklistResults = trade.checklistResults
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            TickerLabel(symbol: trade.symbol)
                .font(.kpiValueSecondary)
            DirectionLabel(direction: trade.direction)
            SessionBadge(session: trade.session)
            Spacer()
            Text(trade.profitDouble.asCurrency)
                .font(.sessionName)
                .fontWeight(.bold)
                .foregroundStyle(Color.forPnL(trade.netProfit))
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Core Details

    private var coreDetails: some View {
        detailSection("Trade Info") {
            detailRow("Direction", trade.direction.rawValue)
            detailRow("Shares", String(format: "%.2f", trade.shares))
            detailRow("Duration", "\(trade.durationMin) min")
            detailRow("Open", "\(trade.openTime.tradeDisplayString) ET")
            detailRow("Close", "\(trade.closeTime.tradeDisplayString) ET")
            detailRow("Trading Day", trade.closeTime.formatted(
                TradingCalendar.formatStyle.weekday(.abbreviated).month(.abbreviated).day().year()
            ))
            detailRow("Hour", "\(trade.hour):00 ET")
        }
    }

    // MARK: - Price Details

    private var priceDetails: some View {
        detailSection("Prices") {
            detailRow("Open Price", "\(trade.openPrice)")
            detailRow("Close Price", "\(trade.closePrice)")
            detailRow("Stop Loss", "\(trade.sl)")
            detailRow("Take Profit", "\(trade.tp)")
            detailRow("SL Distance", trade.slDistPoints.asPoints)
        }
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        detailSection("Performance Metrics") {
            detailRow("P&L", trade.profitDouble.asCurrency, color: Color.forPnL(trade.netProfit))
            detailRow("R-Multiple", trade.rMultiple.asRMultiple, color: Color.forPnL(trade.rMultiple))
            detailRow("MAE", trade.maePoints.asPoints)
            detailRow("MFE", trade.mfePoints.asPoints)
            detailRow("Time to MFE", "\(trade.timeToMFEMin) min")
            detailRow("Slippage", trade.slippagePoints.asPoints)
        }
    }

    // MARK: - Advanced Metrics

    private var advancedMetrics: some View {
        detailSection("Advanced") {
            detailRow("Range Size", String(format: "%.2f", trade.rangeSize))
            detailRow("Hit BE", trade.hitBreakeven ? "Yes" : "No")
            detailRow("Scaled In", trade.scaledIn ? "Yes" : "No")
            if !trade.sector.isEmpty {
                detailRow("Sector", trade.sector)
            }
            if !trade.industry.isEmpty {
                detailRow("Industry", trade.industry)
            }
            if trade.volume > 0 {
                detailRow("Volume", "\(trade.volume)")
            }
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        detailSection("Tags") {
            FlowLayout(spacing: 6) {
                ForEach(tradeTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.smallText)
                        Button {
                            removeTag(tag)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.monoSmall)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accent.opacity(0.15))
                    .clipShape(Capsule())
                }

                // Add tag input
                HStack(spacing: 4) {
                    TextField("Add tag...", text: $newTag)
                        .font(.smallText)
                        .textFieldStyle(.plain)
                        .frame(width: 80)
                        .onSubmit { addTag() }
                    Button {
                        addTag()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.smallText)
                            .foregroundStyle(Color.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(newTag.isEmpty)
                }
            }

            // Quick tag suggestions
            HStack(spacing: 4) {
                ForEach(["setup-A", "revenge", "FOMO", "sniper", "grind"], id: \.self) { suggestion in
                    Button(suggestion) {
                        newTag = suggestion
                        addTag()
                    }
                    .font(.smallText)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }
        var existing = tradeTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !existing.contains(tag) {
            existing.append(tag)
            tradeTags = existing.joined(separator: ",")
            saveTags()
        }
        newTag = ""
    }

    private func removeTag(_ tag: String) {
        var existing = tradeTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        existing.removeAll { $0 == tag }
        tradeTags = existing.joined(separator: ",")
        saveTags()
    }

    private func saveTags() {
        guard let id = trade.id else { return }
        do {
            try appState.tradeRepository.updateTags(tradeId: id, tags: tradeTags)
        } catch {
            Self.logger.error("Failed to save tags: \(error.localizedDescription)")
            appState.showToast(.error, "Failed to save tags")
        }
    }

    // MARK: - Emotion

    private var emotionSection: some View {
        detailSection("Emotional State") {
            FlowLayout(spacing: 6) {
                ForEach(TradeEmotion.allCases, id: \.rawValue) { emotion in
                    Button {
                        let newValue = selectedEmotion == emotion.rawValue ? "" : emotion.rawValue
                        selectedEmotion = newValue
                        saveEmotion(newValue)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: emotion.icon)
                                .font(.smallText)
                            Text(emotion.displayName)
                                .font(.smallText)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(selectedEmotion == emotion.rawValue ? emotionColor(emotion).opacity(0.25) : Color.clear)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(
                            selectedEmotion == emotion.rawValue ? emotionColor(emotion) : Color.secondary.opacity(0.3),
                            lineWidth: selectedEmotion == emotion.rawValue ? 1.5 : 0.5
                        ))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func emotionColor(_ emotion: TradeEmotion) -> Color {
        switch emotion {
        case .calm: Color.semanticGreen
        case .confident: Color.semanticBlue
        case .anxious: .yellow
        case .frustrated: .orange
        case .revenge: Color.semanticRed
        case .fomo: Color.semanticPurple
        case .bored: .gray
        }
    }

    private func saveEmotion(_ value: String) {
        guard let id = trade.id else { return }
        do {
            try appState.tradeRepository.updateEmotion(tradeId: id, emotion: value)
        } catch {
            Self.logger.error("Failed to save emotion: \(error.localizedDescription)")
            appState.showToast(.error, "Failed to save emotion")
        }
    }

    // MARK: - Costs

    private var costsSection: some View {
        detailSection("Trading Costs") {
            HStack {
                Text("Commission")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                TextField("0.00", text: $commissionText)
                    .font(.monoSubtitle)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .textFieldStyle(.plain)
                    .onChange(of: commissionText) { debouncedCostsSave() }
            }
            HStack {
                Text("Swap")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                TextField("0.00", text: $swapText)
                    .font(.monoSubtitle)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .textFieldStyle(.plain)
                    .onChange(of: swapText) { debouncedCostsSave() }
            }
            if let comm = Decimal(string: commissionText), let sw = Decimal(string: swapText), (comm + sw) > 0 {
                let total = comm + sw
                detailRow("Total Costs", "-\(NSDecimalNumber(decimal: total).doubleValue.asCurrency)", color: .semanticRed)
                // Stored P&L is already net of costs; show what it was before them
                detailRow("Gross Before Costs", NSDecimalNumber(decimal: trade.netProfit + total).doubleValue.asCurrency,
                          color: Color.forPnL(NSDecimalNumber(decimal: trade.netProfit + total).doubleValue))
            }
        }
    }

    private func debouncedCostsSave() {
        costsSaveTask?.cancel()
        costsSaveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveCosts()
        }
    }

    private func saveCosts() {
        guard let id = trade.id else { return }
        let commission = Decimal(string: commissionText) ?? 0
        let swap = Decimal(string: swapText) ?? 0
        do {
            try appState.tradeRepository.updateCosts(tradeId: id, commission: commission, swap: swap)
        } catch {
            Self.logger.error("Failed to save costs: \(error.localizedDescription)")
            appState.showToast(.error, "Failed to save costs")
        }
    }

    // MARK: - Checklist

    private var checklistSection: some View {
        detailSection("Checklist") {
            let rules = UserDefaults.standard.stringArray(forKey: "trading_checklist") ?? []
            if rules.isEmpty {
                Text("No checklist rules configured. Add rules in Dashboard → Checklist Analytics.")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
            } else {
                ForEach(rules, id: \.self) { rule in
                    HStack {
                        Button {
                            checklistResults[rule] = !(checklistResults[rule] ?? false)
                            saveChecklist()
                        } label: {
                            Image(systemName: checklistResults[rule] == true ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(checklistResults[rule] == true ? Color.semanticGreen : Color.secondary)
                                .font(.bodyText)
                        }
                        .buttonStyle(.plain)
                        Text(rule)
                            .font(.smallText)
                            .foregroundStyle(checklistResults[rule] == true ? .primary : .secondary)
                        Spacer()
                    }
                }
            }
        }
    }

    private func saveChecklist() {
        guard let id = trade.id else { return }
        guard let data = try? JSONEncoder().encode(checklistResults),
              let json = String(data: data, encoding: .utf8) else { return }
        do {
            try appState.tradeRepository.updateChecklist(tradeId: id, checklistData: json)
        } catch {
            Self.logger.error("Failed to save checklist: \(error.localizedDescription)")
            appState.showToast(.error, "Failed to save checklist")
        }
    }

    // MARK: - Screenshots

    private var screenshotsSection: some View {
        detailSection("Screenshots") {
            if trade.id != nil {
                TradeScreenshots(trade: trade)
            } else {
                Text("Save trade to add screenshots")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        detailSection("Notes") {
            TextEditor(text: $tradeNotes)
                .font(.smallText)
                .frame(minHeight: 60)
                .scrollContentBackground(.hidden)
                .onChange(of: tradeNotes) {
                    notesSaveTask?.cancel()
                    notesSaveTask = Task {
                        try? await Task.sleep(for: .seconds(1))
                        guard !Task.isCancelled, let id = trade.id else { return }
                        do {
                            try appState.tradeRepository.updateNotes(tradeId: id, notes: tradeNotes)
                        } catch {
                            Self.logger.error("Failed to save notes: \(error.localizedDescription)")
                            appState.showToast(.error, "Failed to save notes")
                        }
                    }
                }
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        detailSection("Metadata") {
            detailRow("Ticket", "\(trade.ticket)")

            if !trade.comment.isEmpty {
                detailRow("Comment", trade.comment)
            }
            detailRow("Imported", trade.importedAt.tradeDisplayString)
        }
    }

    // MARK: - Helpers

    private func detailSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.smallText)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)
            VStack(spacing: 4) {
                content()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
   .overlay(
       RoundedRectangle(cornerRadius: 12)
           .stroke(Color.borderCard, lineWidth: 1)
   )
    }

    private func detailRow(_ label: String, _ value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.monoSubtitle)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
