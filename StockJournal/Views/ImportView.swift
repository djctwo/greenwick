import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Bindable var viewModel: ImportViewModel
    @Environment(\.appState) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            dropZone
            supportedPlatforms
            importActions
            importHistory
            Spacer()
        }
        .padding(24)
        .navigationTitle("Import Trades")
        .fileImporter(
            isPresented: $viewModel.showFileImporter,
            allowedContentTypes: [.commaSeparatedText, UTType(filenameExtension: "csv")!],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    Task { await viewModel.importFile(at: url) }
                }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $viewModel.showColumnMapping) {
            if let pending = viewModel.pendingFile {
                ColumnMappingSheet(
                    headers: pending.detection.headers,
                    sampleRows: pending.detection.sampleRows,
                    onConfirm: { mapping in
                        Task { await viewModel.confirmManualMapping(mapping) }
                    },
                    onCancel: { viewModel.cancelManualMapping() }
                )
            }
        }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.kpiValue)
                .foregroundStyle(viewModel.isDragOver ? Color.accent : .secondary)

            Text("Drop CSV Trade Export Here")
                .font(.cardTitle)
                .fontWeight(.medium)

            Text("Auto-detects Robinhood, Schwab, Fidelity, ThinkorSwim, and more")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)

            if viewModel.isImporting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Importing trades...")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    viewModel.isDragOver ? Color.accent : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
        )
        .background(
            viewModel.isDragOver
            ? Color.accent.opacity(0.05)
            : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
       .overlay(
           RoundedRectangle(cornerRadius: 12)
               .stroke(Color.borderCard, lineWidth: 1)
       )
        .contentShape(Rectangle())
        .accessibilityIdentifier("import.dropZone")
        .onDrop(of: [.fileURL], isTargeted: $viewModel.isDragOver) { providers in
            viewModel.handleDrop(providers: providers)
        }
    }

    // MARK: - Supported Platforms

    @State private var expandedPlatform: String?

    private var supportedPlatforms: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Supported Platforms")
                .font(.smallText)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)

            VStack(spacing: 4) {
                ForEach(platformItems, id: \.name) { item in
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            if reduceMotion {
                                expandedPlatform = expandedPlatform == item.name ? nil : item.name
                            } else {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedPlatform = expandedPlatform == item.name ? nil : item.name
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: item.icon)
                                    .font(.smallText)
                                    .foregroundStyle(Color.accent)
                                    .frame(width: 14)
                                Text(item.name)
                                    .font(.smallText)
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                Image(systemName: expandedPlatform == item.name ? "chevron.up" : "chevron.down")
                                    .font(.smallText)
                                    .foregroundStyle(Color.textTertiary)
                            }
                            // Whole row is clickable, not just the name and chevron
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)

                        if expandedPlatform == item.name {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(item.exports, id: \.name) { export in
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "checkmark")
                                            .font(.smallText)
                                            .foregroundStyle(Color.semanticGreen)
                                            .frame(width: 12)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(export.name)
                                                .font(.smallText)
                                                .fontWeight(.medium)
                                            Text(export.path)
                                                .font(.smallText)
                                                .foregroundStyle(Color.textTertiary)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .background(Color.bgCard.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.borderCard, lineWidth: 1)
                    )
                }
            }
        }
    }

    private struct PlatformExport {
        let name: String
        let path: String
    }

    private var platformItems: [(name: String, icon: String, exports: [PlatformExport])] {
        [
            ("Thinkorswim", "waveform.path.ecg", [
                PlatformExport(name: "Account Statement", path: "Monitor tab → Account Statement → Export as CSV"),
            ]),
            ("Webull", "chart.line.uptrend.xyaxis", [
                PlatformExport(name: "Trade History", path: "Account → Trade History → Export CSV"),
            ]),
            ("Interactive Brokers", "building.columns", [
                PlatformExport(name: "Activity Statement", path: "Client Portal → Performance & Reports → Statements → Activity → CSV"),
                PlatformExport(name: "Flex Query", path: "Client Portal → Flex Queries → Trade Confirmation → CSV"),
            ]),
            ("TradingView", "tv", [
                PlatformExport(name: "Trade History", path: "Trading Panel → History → Export to CSV"),
            ]),
            ("NinjaTrader", "flame", [
                PlatformExport(name: "Trade History", path: "Control Center → Account → Trade History → Export"),
            ]),
            ("Robinhood", "dollarsign.circle", [
                PlatformExport(name: "Account History", path: "Account → Statements & History → Account → Export CSV"),
            ]),
            ("Charles Schwab", "building.2", [
                PlatformExport(name: "Transaction History", path: "Accounts → History → Export → CSV"),
            ]),
            ("Fidelity", "shield", [
                PlatformExport(name: "Activity & Orders", path: "Accounts → Activity & Orders → Download"),
            ]),
            ("E*Trade", "chart.bar.xaxis", [
                PlatformExport(name: "Transaction History (Website)", path: "Accounts → Transaction History → Download"),
                PlatformExport(name: "Power E*Trade", path: "History → Export (includes execution time)"),
            ]),
            ("Tastytrade", "flame.circle", [
                PlatformExport(name: "Transaction History", path: "History tab → Download CSV"),
                PlatformExport(name: "YTD Download", path: "History → Download YTD Transactions"),
            ]),
            ("Generic CSV", "doc.text", [
                PlatformExport(name: "Any CSV", path: "Columns: Symbol, Direction, Shares, Date, Price, P&L"),
            ]),
        ]
    }

    // MARK: - Import Actions

    private var importActions: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.showFileImporter = true
            } label: {
                Label("Choose File", systemImage: "folder")
            }
            .accessibilityIdentifier("import.chooseFile")
            .controlSize(.large)
            .disabled(viewModel.isImporting)

            Button {
                viewModel.showFolderPicker()
            } label: {
                Label("Scan Folder", systemImage: "folder.badge.gearshape")
            }
            .controlSize(.large)
            .disabled(viewModel.isImporting)
            .help("Choose a folder to scan for CSV trade exports")
        }
    }

    // MARK: - Import History

    @ViewBuilder
    private var importHistory: some View {
        if !viewModel.importResults.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Import History")
                        .font(.cardTitle)
                    Spacer()
                    Button("Clear") { viewModel.clearHistory() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.textSecondary)
                        .font(.smallText)
                }

                ForEach(Array(viewModel.importResults.enumerated()), id: \.offset) { _, result in
                    HStack {
                        Image(systemName: result.errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(result.errors.isEmpty ? Color.semanticGreen : Color.semanticRed)
                            .font(.smallText)
                        Text(result.filename)
                            .font(.smallText)
                            .fontWeight(.medium)
                        Spacer()
                        Text(result.summary)
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(8)
                    .background(Color.bgContent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
               .overlay(
                   RoundedRectangle(cornerRadius: 12)
                       .stroke(Color.borderCard, lineWidth: 1)
               )
                }
            }
        }

        if let error = viewModel.errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(error)
                    .font(.smallText)
                    .foregroundStyle(Color.semanticRed)
                Spacer()
                Button("Dismiss") { viewModel.errorMessage = nil }
                    .font(.smallText)
            }
            .padding(10)
            .background(Color.semanticRed.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
       .overlay(
           RoundedRectangle(cornerRadius: 12)
               .stroke(Color.borderCard, lineWidth: 1)
       )
        }
    }
}

// MARK: - Column Mapping Sheet

/// Manual column mapping UI for unknown CSV formats
struct ColumnMappingSheet: View {
    let headers: [String]
    let sampleRows: [[String]]
    let onConfirm: (GenericCSVParser.ColumnMapping) -> Void
    let onCancel: () -> Void

    @State private var symbolCol = 0
    @State private var directionCol = 0
    @State private var sharesCol = 0
    @State private var openTimeCol = 0
    @State private var closeTimeCol: Int? = nil
    @State private var openPriceCol = 0
    @State private var closePriceCol: Int? = nil
    @State private var profitCol = 0
    @State private var slCol: Int? = nil
    @State private var tpCol: Int? = nil
    @State private var ticketCol: Int? = nil
    @State private var commissionCol: Int? = nil
    @State private var swapCol: Int? = nil
    @State private var dateFormat = "yyyy-MM-dd HH:mm:ss"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Map CSV Columns")
                    .font(.cardTitle)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            // Preview
            csvPreview
                .padding()

            Divider()

            // Mapping form
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Required Fields")
                        .font(.smallText)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textSecondary)

                    mappingRow("Symbol", selection: $symbolCol)
                    mappingRow("Direction (Buy/Sell)", selection: $directionCol)
                    mappingRow("Shares / Quantity", selection: $sharesCol)
                    mappingRow("Open Time", selection: $openTimeCol)
                    mappingRow("Open Price", selection: $openPriceCol)
                    mappingRow("Profit/P&L", selection: $profitCol)

                    Divider()

                    Text("Optional Fields")
                        .font(.smallText)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textSecondary)

                    optionalMappingRow("Close Time", selection: $closeTimeCol)
                    optionalMappingRow("Close Price", selection: $closePriceCol)
                    optionalMappingRow("Stop Loss", selection: $slCol)
                    optionalMappingRow("Take Profit", selection: $tpCol)
                    optionalMappingRow("Ticket/ID", selection: $ticketCol)
                    optionalMappingRow("Commission", selection: $commissionCol)
                    optionalMappingRow("Swap/Financing", selection: $swapCol)

                    Divider()

                    HStack {
                        Text("Date Format")
                            .font(.smallText)
                            .frame(width: 140, alignment: .leading)
                        TextField("yyyy-MM-dd HH:mm:ss", text: $dateFormat)
                            .textFieldStyle(.roundedBorder)
                            .font(.monoSubtitle)
                    }
                }
                .padding()
            }

            Divider()

            // Actions
            HStack {
                Spacer()
                Button("Import") {
                    let mapping = GenericCSVParser.ColumnMapping(
                        platform: .generic,
                        ticket: ticketCol,
                        symbol: symbolCol,
                        direction: directionCol,
                        shares: sharesCol,
                        openTime: openTimeCol,
                        closeTime: closeTimeCol,
                        openPrice: openPriceCol,
                        closePrice: closePriceCol,
                        sl: slCol,
                        tp: tpCol,
                        profit: profitCol,
                        commission: commissionCol,
                        swap: swapCol,
                        maePoints: nil,
                        mfePoints: nil,
                        volume: nil,
                        dateFormat: dateFormat
                    )
                    onConfirm(mapping)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
        .frame(width: 600, height: 650)
        .onAppear { autoAssignColumns() }
    }

    // MARK: - CSV Preview

    private var csvPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("File Preview")
                .font(.smallText)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)

            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 2) {
                    // Header row
                    HStack(spacing: 0) {
                        ForEach(Array(headers.enumerated()), id: \.offset) { i, header in
                            Text(header)
                                .font(.monoSubtitle)
                                .fontWeight(.bold)
                                .frame(width: 100, alignment: .leading)
                                .padding(2)
                                .background(i % 2 == 0 ? Color.clear : Color.secondary.opacity(0.05))
                        }
                    }
                    Divider()
                    // Sample rows
                    ForEach(Array(sampleRows.prefix(3).enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { i, field in
                                Text(field)
                                    .font(.monoSubtitle)
                                    .frame(width: 100, alignment: .leading)
                                    .padding(2)
                                    .lineLimit(1)
                                    .background(i % 2 == 0 ? Color.clear : Color.secondary.opacity(0.05))
                            }
                        }
                    }
                }
            }
            .padding(8)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
       .overlay(
           RoundedRectangle(cornerRadius: 12)
               .stroke(Color.borderCard, lineWidth: 1)
       )
        }
    }

    // MARK: - Mapping Rows

    private func mappingRow(_ label: String, selection: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .font(.smallText)
                .frame(width: 140, alignment: .leading)
            Picker("", selection: selection) {
                ForEach(Array(headers.enumerated()), id: \.offset) { i, header in
                    Text("\(i): \(header)").tag(i)
                }
            }
            .labelsHidden()
            .frame(width: 200)
        }
    }

    private func optionalMappingRow(_ label: String, selection: Binding<Int?>) -> some View {
        HStack {
            Text(label)
                .font(.smallText)
                .frame(width: 140, alignment: .leading)
            Picker("", selection: selection) {
                Text("— None —").tag(nil as Int?)
                ForEach(Array(headers.enumerated()), id: \.offset) { i, header in
                    Text("\(i): \(header)").tag(i as Int?)
                }
            }
            .labelsHidden()
            .frame(width: 200)
        }
    }

    // MARK: - Auto-assign

    /// Best-effort auto-assign columns based on header names
    private func autoAssignColumns() {
        let h = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        if let i = h.firstIndex(where: { $0.contains("symbol") || $0.contains("pair") || $0.contains("instrument") || $0.contains("item") }) {
            symbolCol = i
        }
        if let i = h.firstIndex(where: { $0.contains("direction") || $0.contains("type") || $0.contains("side") || $0.contains("buy") }) {
            directionCol = i
        }
        if let i = h.firstIndex(where: { $0.contains("lot") || $0.contains("volume") || $0.contains("size") || $0.contains("qty") || $0.contains("quantity") || $0.contains("units") || $0.contains("contracts") }) {
            sharesCol = i
        }
        if let i = h.firstIndex(where: { $0.contains("open time") || $0.contains("entry time") || $0.contains("date") || $0.contains("time") }) {
            openTimeCol = i
        }
        if let i = h.firstIndex(where: { $0.contains("open price") || $0.contains("entry price") || $0.contains("price") }) {
            openPriceCol = i
        }
        if let i = h.firstIndex(where: { $0.contains("profit") || $0.contains("p/l") || $0.contains("p&l") || $0.contains("net") }) {
            profitCol = i
        }
        closeTimeCol = h.firstIndex(where: { $0.contains("close time") || $0.contains("exit time") || $0.contains("closing time") })
        closePriceCol = h.firstIndex(where: { $0.contains("close price") || $0.contains("exit price") || $0.contains("closing price") })
        slCol = h.firstIndex(where: { $0.contains("stop loss") || $0 == "sl" || $0 == "s/l" })
        tpCol = h.firstIndex(where: { $0.contains("take profit") || $0 == "tp" || $0 == "t/p" })
        ticketCol = h.firstIndex(where: { $0.contains("ticket") || $0.contains("trade #") || $0.contains("id") || $0.contains("positionid") })
        commissionCol = h.firstIndex(where: { $0.contains("commission") || $0.contains("comm") })
        swapCol = h.firstIndex(where: { $0.contains("swap") || $0.contains("financing") || $0.contains("interest") })
    }
}
