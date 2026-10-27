import SwiftUI

/// Tracks trading rule/checklist compliance and shows the dollar impact
/// of following vs breaking each rule
struct ChecklistAnalytics: View {
    let trades: [Trade]

    private struct RuleStats: Identifiable {
        let id: String
        let rule: String
        let complianceRate: Double
        let avgPnLFollowed: Double
        let avgPnLBroken: Double
        let dollarImpact: Double
        let winRateFollowed: Double
        let winRateBroken: Double
    }

    // MARK: - Analysis

    private var clTrades: [Trade] { trades.filter { !$0.checklistResults.isEmpty } }
    private var hasData: Bool { clTrades.count >= 5 }

    private var ruleStats: [RuleStats] {
        guard hasData else { return [] }
        var followed: [String: [Trade]] = [:]
        var broken: [String: [Trade]] = [:]
        for trade in clTrades {
            for (rule, ok) in trade.checklistResults {
                if ok { followed[rule, default: []].append(trade) }
                else { broken[rule, default: []].append(trade) }
            }
        }
        return Set(followed.keys).union(broken.keys).map { rule in
            let f = followed[rule] ?? [], b = broken[rule] ?? []
            let total = f.count + b.count
            let avgF = f.isEmpty ? 0 : f.map(\.profitDouble).reduce(0, +) / Double(f.count)
            let avgB = b.isEmpty ? 0 : b.map(\.profitDouble).reduce(0, +) / Double(b.count)
            let wrF = f.isEmpty ? 0 : Double(f.filter(\.isWin).count) / Double(f.count) * 100
            let wrB = b.isEmpty ? 0 : Double(b.filter(\.isWin).count) / Double(b.count) * 100
            return RuleStats(id: rule, rule: rule,
                             complianceRate: total > 0 ? Double(f.count) / Double(total) * 100 : 0,
                             avgPnLFollowed: avgF, avgPnLBroken: avgB,
                             dollarImpact: avgF - avgB,
                             winRateFollowed: wrF, winRateBroken: wrB)
        }.sorted { $0.dollarImpact > $1.dollarImpact }
    }

    private var overallCompliance: Double {
        guard hasData else { return 0 }
        var total = 0, checked = 0
        for trade in clTrades {
            for (_, v) in trade.checklistResults { total += 1; if v { checked += 1 } }
        }
        return total > 0 ? Double(checked) / Double(total) * 100 : 0
    }

    private var allFollowedAvg: Double {
        let full = clTrades.filter { $0.checklistResults.values.allSatisfy { $0 } }
        guard !full.isEmpty else { return 0 }
        return full.map(\.profitDouble).reduce(0, +) / Double(full.count)
    }

    private var anyBrokenAvg: Double {
        let partial = clTrades.filter { $0.checklistResults.values.contains(false) }
        guard !partial.isEmpty else { return 0 }
        return partial.map(\.profitDouble).reduce(0, +) / Double(partial.count)
    }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Checklist Compliance", systemImage: "checklist")
                    .font(.cardTitle)
                Spacer()
                Text("\(clTrades.count)/\(trades.count) with checklist")
                    .font(.smallText).foregroundStyle(Color.textTertiary)
            }
            if !hasData {
                Text("Need at least 5 trades with checklist data")
                    .font(.smallText).foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                HStack(spacing: 12) { complianceGauge; summaryBar }
                Divider().opacity(0.3)
                ForEach(ruleStats) { ruleRow($0) }
            }
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderCard, lineWidth: 1))
    }

    // MARK: - Subviews

    private var complianceGauge: some View {
        ZStack {
            Circle().stroke(Color.accent.opacity(0.15), lineWidth: 5)
            Circle().trim(from: 0, to: overallCompliance / 100)
                .stroke(Color.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(String(format: "%.0f%%", overallCompliance))
                    .font(.monoSubtitle).fontWeight(.bold)
                    .foregroundStyle(Color.accent)
                Text("COMP").font(.monoSmall).foregroundStyle(Color.textTertiary)
            }
        }
        .frame(width: 52, height: 52)
    }

    private var summaryBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            summaryLine(icon: "checkmark.circle.fill", color: .semanticGreen,
                        label: "All rules followed:", value: allFollowedAvg)
            summaryLine(icon: "xmark.circle.fill", color: .semanticRed,
                        label: "Breaking rules:", value: anyBrokenAvg)
        }
    }

    private func summaryLine(icon: String, color: Color, label: String, value: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.smallText).foregroundStyle(color)
            Text(label).font(.smallText).foregroundStyle(Color.textSecondary)
            Text(value.asCurrency).font(.monoSubtitle)
                .fontWeight(.medium).foregroundStyle(Color.forPnL(value))
            Text("avg").font(.monoSmall).foregroundStyle(Color.textTertiary)
        }
    }

    private func ruleRow(_ stat: RuleStats) -> some View {
        let isBest = stat.id == ruleStats.first?.id
        let isWorst = stat.id == ruleStats.last?.id && ruleStats.count > 1

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stat.rule).font(.smallText)
                    .fontWeight(isBest || isWorst ? .semibold : .regular).lineLimit(1)
                if isBest {
                    badge("BEST", color: .semanticGreen)
                } else if isWorst && stat.dollarImpact < 0 {
                    badge("WORST", color: .semanticRed)
                }
                Spacer()
                Text(impactString(stat.dollarImpact))
                    .font(.monoSubtitle).fontWeight(.medium)
                    .foregroundStyle(Color.forPnL(stat.dollarImpact))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.1))
                    RoundedRectangle(cornerRadius: 2).fill(Color.accent.opacity(0.6))
                        .frame(width: max(2, geo.size.width * stat.complianceRate / 100))
                }
            }.frame(height: 4)
            HStack(spacing: 0) {
                Text(String(format: "%.0f%% compliance", stat.complianceRate))
                    .font(.monoSmall).foregroundStyle(Color.textTertiary)
                Spacer()
                statLabel("Followed:", stat.avgPnLFollowed, stat.winRateFollowed)
                statLabel("  Broken:", stat.avgPnLBroken, stat.winRateBroken)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text).font(.monoSmall).fontWeight(.bold)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(color.opacity(0.2)).foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func statLabel(_ prefix: String, _ pnl: Double, _ wr: Double) -> some View {
        HStack(spacing: 0) {
            Text(prefix).font(.monoSmall).foregroundStyle(Color.textTertiary)
            Text(" ").font(.monoSmall)
            Text(pnl.asCurrency).font(.monoSmall)
                .foregroundStyle(Color.forPnL(pnl))
            Text(String(format: " (%.0f%%)", wr)).font(.monoSmall).foregroundStyle(Color.textTertiary)
        }
    }

    private func impactString(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(value.asCurrency)"
    }
}

// MARK: - Checklist Editor

/// Simple list editor for trading checklist rules, persisted in UserDefaults
struct ChecklistEditor: View {
    @Binding var rules: [String]
    @State private var newRule = ""
    private let storageKey = "trading_checklist"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Checklist Rules", systemImage: "checklist.checked").font(.cardTitle)
            HStack(spacing: 8) {
                TextField("New rule...", text: $newRule)
                    .textFieldStyle(.roundedBorder).onSubmit(addRule)
                Button(action: addRule) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
                .disabled(newRule.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if rules.isEmpty {
                Text("No rules yet — add rules to track compliance")
                    .font(.smallText).foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                List {
                    ForEach(rules, id: \.self) { rule in
                        Text(rule).font(.bodyText)
                    }
                    .onDelete(perform: deleteRules)
                }
                .listStyle(.plain).frame(minHeight: 100, maxHeight: 250)
            }
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderCard, lineWidth: 1))
    }

    private func addRule() {
        let trimmed = newRule.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !rules.contains(trimmed) else { return }
        rules.append(trimmed)
        UserDefaults.standard.set(rules, forKey: storageKey)
        newRule = ""
    }

    private func deleteRules(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        UserDefaults.standard.set(rules, forKey: storageKey)
    }
}
