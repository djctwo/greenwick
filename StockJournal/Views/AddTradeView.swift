import Security
import SwiftUI
import os

/// Manual trade entry form — sheet presentation for adding a single trade
struct AddTradeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appState) private var appState

    @State private var viewModel = AddTradeViewModel()
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.borderSubtle)
            ScrollView {
                VStack(spacing: 16) {
                    requiredFields
                    computedPreview
                    moreDetailsSection
                }
                .padding(24)
            }
            Divider().background(Color.borderSubtle)
            footer
        }
        .frame(width: 520)
        .frame(minHeight: 600, maxHeight: 800)
        .background(Color.bgCard)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add Trade")
                    .font(.cardTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("Manual entry")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.bodyText)
                    .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Required Fields

    private var requiredFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TRADE DETAILS")
                .font(.sectionLabel)
                .foregroundStyle(Color.textSecondary)
                .tracking(1.2)

            // Symbol + Direction row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Symbol")
                    TextField("AAPL", text: $viewModel.symbol)
                        .accessibilityIdentifier("addTrade.symbol")
                        .textFieldStyle(.roundedBorder)
                        .font(.tableCell)
                        .onChange(of: viewModel.symbol) { _, newValue in
                            let filtered = newValue.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "." }
                            viewModel.symbol = String(filtered.prefix(10))
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Direction")
                    Picker("Direction", selection: $viewModel.direction) {
                        Text("Buy").tag(TradeDirection.buy)
                        Text("Sell").tag(TradeDirection.sell)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
            }

            // Shares + Open Price + Close Price row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Shares")
                    TextField("100", text: $viewModel.sharesText)
                        .accessibilityIdentifier("addTrade.shares")
                        .textFieldStyle(.roundedBorder)
                        .font(.tableCell)
                }

                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Open Price")
                    TextField("187.42", text: $viewModel.openPriceText)
                        .accessibilityIdentifier("addTrade.openPrice")
                        .textFieldStyle(.roundedBorder)
                        .font(.tableCell)
                }

                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Close Price")
                    TextField("189.10", text: $viewModel.closePriceText)
                        .accessibilityIdentifier("addTrade.closePrice")
                        .textFieldStyle(.roundedBorder)
                        .font(.tableCell)
                }
            }

            // Open Time + Close Time row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Open Time")
                    DatePicker("", selection: $viewModel.openTime)
                        .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Close Time")
                    DatePicker("", selection: $viewModel.closeTime)
                        .labelsHidden()
                }
            }

            // Validation errors
            if !viewModel.validationErrors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.validationErrors, id: \.self) { error in
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.monoSmall)
                            Text(error)
                                .font(.smallText)
                        }
                        .foregroundStyle(Color.semanticRed)
                    }
                }
            }
        }
    }

    // MARK: - Computed Preview

    private var computedPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PREVIEW")
                .font(.sectionLabel)
                .foregroundStyle(Color.textSecondary)
                .tracking(1.2)

            HStack(spacing: 20) {
                previewItem("P&L", viewModel.pnlPreviewText, Color.forPnL(viewModel.pnlPreview))
                previewItem("R-Multiple", viewModel.rMultiplePreviewText, Color.textPrimary)
                previewItem("Duration", viewModel.durationPreviewText, Color.textPrimary)
                previewItem("Session", viewModel.sessionPreview.displayName,
                            Color.forSession(viewModel.sessionPreview))
            }
        }
        .padding(12)
        .background(Color.bgInset)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
    }

    private func previewItem(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.monoSmall)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.monoSubtitle)
                .foregroundStyle(color)
        }
    }

    // MARK: - More Details (Collapsible)

    private var moreDetailsSection: some View {
        DisclosureGroup(isExpanded: $viewModel.showMoreDetails) {
            VStack(alignment: .leading, spacing: 16) {
                // Stop Loss + Take Profit
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Stop Loss")
                        TextField("0.00", text: $viewModel.stopLossText)
                            .textFieldStyle(.roundedBorder)
                            .font(.tableCell)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Take Profit")
                        TextField("0.00", text: $viewModel.takeProfitText)
                            .textFieldStyle(.roundedBorder)
                            .font(.tableCell)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Commission")
                        TextField("0.00", text: $viewModel.commissionText)
                            .textFieldStyle(.roundedBorder)
                            .font(.tableCell)
                    }
                }

                // Sector + Industry
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Sector")
                        TextField("Technology", text: $viewModel.sector)
                            .textFieldStyle(.roundedBorder)
                            .font(.tableCell)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Industry")
                        TextField("Consumer Electronics", text: $viewModel.industry)
                            .textFieldStyle(.roundedBorder)
                            .font(.tableCell)
                    }
                }

                // Volume + Setup
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Volume")
                        TextField("0", text: $viewModel.volumeText)
                            .textFieldStyle(.roundedBorder)
                            .font(.tableCell)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Setup")
                        TextField("ORB, VWAP bounce, gap fill", text: $viewModel.setup)
                            .textFieldStyle(.roundedBorder)
                            .font(.tableCell)
                    }
                }

                // Emotion picker
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Emotion")
                    Picker("Emotion", selection: $viewModel.emotion) {
                        Text("None").tag(TradeEmotion?.none)
                        ForEach(TradeEmotion.allCases, id: \.self) { emotion in
                            Text(emotion.displayName).tag(TradeEmotion?.some(emotion))
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Tags
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Tags")
                    TextField("momentum, earnings, gap-up", text: $viewModel.tags)
                        .textFieldStyle(.roundedBorder)
                        .font(.tableCell)
                }

                // Notes
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Notes")
                    TextEditor(text: $viewModel.notes)
                        .font(.bodyText)
                        .frame(minHeight: 60, maxHeight: 120)
                        .padding(4)
                        .background(Color.bgInset)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.borderSubtle, lineWidth: 1)
                        )
                }
            }
            .padding(.top, 12)
        } label: {
            Text("More Details")
                .font(.cardTitle)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .accessibilityIdentifier("addTrade.cancel")
            .buttonStyle(.plain)
            .foregroundStyle(Color.textSecondary)
            .font(.bodyText)

            Spacer()

            Button {
                saveTrade()
            } label: {
                Text(isSaving ? "Saving..." : "Save Trade")
                    .font(.bodyText)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityIdentifier("addTrade.save")
            .buttonStyle(.plain)
            .disabled(!viewModel.isValid || isSaving)
            .opacity(viewModel.isValid && !isSaving ? 1.0 : 0.5)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.smallText)
            .foregroundStyle(Color.textSecondary)
    }

    private func saveTrade() {
        guard !isSaving, let trade = viewModel.buildTrade() else { return }
        isSaving = true
        do {
            try appState.tradeRepository.insertIfNew(trade)
            appState.showToast(.success, "Trade saved: \(trade.symbol) \(trade.direction.rawValue)")
            dismiss()
        } catch {
            isSaving = false
            appState.showToast(.error, "Failed to save trade: \(error.localizedDescription)")
        }
    }
}

// MARK: - View Model

@Observable
@MainActor
final class AddTradeViewModel {
    private static let logger = Logger(subsystem: "com.greenwick", category: "AddTradeViewModel")

    // Required fields
    var symbol: String = ""
    var direction: TradeDirection = .buy
    var sharesText: String = ""
    var openPriceText: String = ""
    var closePriceText: String = ""
    var openTime: Date = Date()
    var closeTime: Date = Date().addingTimeInterval(30 * 60)

    // Optional fields
    var showMoreDetails: Bool = false
    var stopLossText: String = ""
    var takeProfitText: String = ""
    var commissionText: String = "0.00"
    var sector: String = ""
    var industry: String = ""
    var volumeText: String = ""
    var notes: String = ""
    var emotion: TradeEmotion? = nil
    var setup: String = ""
    var tags: String = ""

    // MARK: - Parsed Values

    private var shares: Double? { Double(sharesText) }
    private var openPrice: Decimal? { Decimal(string: openPriceText) }
    private var closePrice: Decimal? { Decimal(string: closePriceText) }
    private var stopLoss: Decimal? { Decimal(string: stopLossText) }
    private var takeProfit: Decimal? { Decimal(string: takeProfitText) }
    private var commission: Decimal { Decimal(string: commissionText) ?? 0 }
    private var volume: Int { Int(volumeText) ?? 0 }

    private var directionMultiplier: Decimal {
        direction == .buy ? 1 : -1
    }

    // MARK: - Validation

    var validationErrors: [String] {
        var errors: [String] = []
        if symbol.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Symbol is required")
        }
        if let s = shares, s <= 0 {
            errors.append("Shares must be greater than 0")
        } else if shares == nil && !sharesText.isEmpty {
            errors.append("Shares must be a valid number")
        } else if sharesText.isEmpty {
            errors.append("Shares is required")
        }
        if let p = openPrice, p <= 0 {
            errors.append("Open price must be greater than 0")
        } else if openPrice == nil && !openPriceText.isEmpty {
            errors.append("Open price must be a valid number")
        } else if openPriceText.isEmpty {
            errors.append("Open price is required")
        }
        if let p = closePrice, p <= 0 {
            errors.append("Close price must be greater than 0")
        } else if closePrice == nil && !closePriceText.isEmpty {
            errors.append("Close price must be a valid number")
        } else if closePriceText.isEmpty {
            errors.append("Close price is required")
        }
        if closeTime <= openTime {
            errors.append("Close time must be after open time")
        }
        return errors
    }

    var isValid: Bool { validationErrors.isEmpty }

    // MARK: - Computed Previews

    var pnlPreview: Double {
        guard let shares, let openPrice, let closePrice else { return 0 }
        let diff = (closePrice - openPrice) * Decimal(shares) * directionMultiplier - commission
        return NSDecimalNumber(decimal: diff).doubleValue
    }

    var pnlPreviewText: String {
        let value = pnlPreview
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "$%.2f", value))"
    }

    var rMultiplePreviewText: String {
        guard let shares, let openPrice, let stopLoss, stopLoss > 0 else { return "--" }
        let riskPerShare = abs(NSDecimalNumber(decimal: openPrice - stopLoss).doubleValue)
        guard riskPerShare > 0 else { return "--" }
        let risk = riskPerShare * shares
        guard risk > 0 else { return "--" }
        let rMultiple = pnlPreview / risk
        return String(format: "%.1fR", rMultiple)
    }

    var durationPreviewText: String {
        let minutes = Int(saturating: closeTime.timeIntervalSince(openTime) / 60)
        if minutes < 0 { return "--" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remaining = minutes % 60
        return "\(hours)h \(remaining)m"
    }

    var sessionPreview: MarketSession {
        openTime.marketSession
    }

    // MARK: - Build Trade

    func buildTrade() -> Trade? {
        guard isValid,
              let shares,
              let openPrice,
              let closePrice else { return nil }

        let durationMin = max(0, Int(saturating: closeTime.timeIntervalSince(openTime) / 60))
        let pnlDecimal = (closePrice - openPrice) * Decimal(shares) * directionMultiplier - commission
        let pnlDouble = NSDecimalNumber(decimal: pnlDecimal).doubleValue

        let sl = stopLoss ?? 0
        let tp = takeProfit ?? 0

        // Compute R-multiple if SL is set
        let slDistPoints = abs(NSDecimalNumber(decimal: openPrice - sl).doubleValue)
        let rMultiple: Double
        if slDistPoints > 0 {
            let risk = slDistPoints * shares
            rMultiple = pnlDouble / risk
        } else {
            rMultiple = 0
        }

        // Generate unique ticket: microsecond timestamp + random entropy
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000_000)
        var randomBytes: UInt16 = 0
        withUnsafeMutableBytes(of: &randomBytes) { buffer in
            _ = SecRandomCopyBytes(kSecRandomDefault, 2, buffer.baseAddress!)
        }
        let ticket = timestamp + Int64(randomBytes)

        let session = openTime.marketSession
        let dayName = openTime.shortDayName
        let hour = openTime.etHour

        // Build comma-separated tags with setup prepended if present
        var finalTags = tags
        if !setup.trimmingCharacters(in: .whitespaces).isEmpty {
            let setupTag = "setup:\(setup.trimmingCharacters(in: .whitespaces))"
            finalTags = finalTags.isEmpty ? setupTag : "\(setupTag),\(finalTags)"
        }

        return Trade(
            id: nil,
            ticket: ticket,
            symbol: symbol.trimmingCharacters(in: .whitespaces).uppercased(),
            direction: direction,
            shares: shares,
            openTime: openTime,
            closeTime: closeTime,
            durationMin: durationMin,
            openPrice: openPrice,
            closePrice: closePrice,
            sl: sl,
            tp: tp,
            netProfit: pnlDecimal,
            maePoints: 0,
            mfePoints: 0,
            rMultiple: rMultiple,
            session: session,
            dayOfWeek: dayName,
            hour: hour,
            rangeSize: 0,
            hitBreakeven: false,
            scaledIn: false,
            comment: "MAN-\(timestamp)",
            timeToMFEMin: 0,
            slDistPoints: slDistPoints,
            slippagePoints: 0,
            sector: sector,
            industry: industry,
            volume: volume,
            avgVolume: 0,
            notes: notes,
            tags: finalTags,
            emotion: emotion?.rawValue ?? "",
            screenshots: "",
            checklistData: "",
            commission: commission,
            swap: 0,
            importedAt: Date()
        )
    }
}
