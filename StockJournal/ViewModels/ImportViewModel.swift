import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import os

/// ViewModel for the Import view — handles file selection, format detection, and import
@Observable
@MainActor
final class ImportViewModel {
    private let repository: TradeRepository
    private static let logger = Logger(subsystem: "com.greenwick", category: "ImportVM")

    var isImporting = false
    var importResults: [ImportResult] = []
    var isDragOver = false
    var showFileImporter = false
    var errorMessage: String?
    var onImportSuccess: (() -> Void)?

    // MARK: - Format Detection State

    var pendingFile: PendingImport?
    var showColumnMapping = false

    struct PendingImport: Sendable {
        let url: URL
        let detection: GenericCSVParser.DetectionResult
    }

    struct ImportResult: Sendable {
        let totalParsed: Int
        let newlyImported: Int
        let duplicatesSkipped: Int
        let errors: [String]
        let filename: String

        var summary: String {
            "\(filename): \(newlyImported) imported, \(duplicatesSkipped) duplicates, \(errors.count) errors"
        }
    }

    init(repository: TradeRepository) {
        self.repository = repository
    }

    // MARK: - Actions

    /// Import from a file URL — auto-detects format
    func importFile(at url: URL) async {
        let path = url.path
        let filename = url.lastPathComponent

        do {
            // Parse off the main thread so a large file never freezes the window
            let detection = try await Task.detached(priority: .userInitiated) {
                try GenericCSVParser.detect(fileAt: path)
            }.value

            switch detection.platform {
            case .generic:
                pendingFile = PendingImport(url: url, detection: detection)
                showColumnMapping = true

            default:
                guard let mapping = detection.mapping else {
                    errorMessage = "Could not map columns for \(detection.platform.rawValue)"
                    return
                }
                await importWithMapping(url: url, mapping: mapping, platformName: detection.platform.rawValue)
            }
        } catch {
            let result = ImportResult(
                totalParsed: 0,
                newlyImported: 0,
                duplicatesSkipped: 0,
                errors: [error.localizedDescription],
                filename: filename
            )
            importResults.insert(result, at: 0)
            errorMessage = error.localizedDescription
        }
    }

    /// Import using a column mapping
    func importWithMapping(url: URL, mapping: GenericCSVParser.ColumnMapping, platformName: String) async {
        let filename = url.lastPathComponent
        isImporting = true
        defer { isImporting = false }

        do {
            let path = url.path
            let trades = try await Task.detached(priority: .userInitiated) {
                try GenericCSVParser.parse(fileAt: path, mapping: mapping)
            }.value
            let insertedCount = try repository.bulkInsert(trades)
            let result = ImportResult(
                totalParsed: trades.count,
                newlyImported: insertedCount,
                duplicatesSkipped: trades.count - insertedCount,
                errors: [],
                filename: filename
            )
            Self.logger.info("\(platformName) import: \(result.summary)")
            importResults.insert(result, at: 0)
            if insertedCount > 0 {
                onImportSuccess?()
            }
        } catch {
            let result = ImportResult(
                totalParsed: 0,
                newlyImported: 0,
                duplicatesSkipped: 0,
                errors: [error.localizedDescription],
                filename: filename
            )
            importResults.insert(result, at: 0)
            errorMessage = error.localizedDescription
        }
    }

    /// Confirm import with manual column mapping
    func confirmManualMapping(_ mapping: GenericCSVParser.ColumnMapping) async {
        guard let pending = pendingFile else { return }
        showColumnMapping = false
        await importWithMapping(url: pending.url, mapping: mapping, platformName: "Generic CSV")
        pendingFile = nil
    }

    /// Cancel pending manual mapping
    func cancelManualMapping() {
        showColumnMapping = false
        pendingFile = nil
    }

    /// Handle dropped file URLs
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          url.pathExtension.lowercased() == "csv" else { return }
                    Task { @MainActor in
                        await self.importFile(at: url)
                    }
                }
            }
        }
        return handled
    }

    /// Show folder picker and scan selected folder for CSVs
    func showFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose Folder to Scan"
        panel.message = "Select a folder containing CSV trade exports"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }
        Task { await scanFolder(at: folderURL) }
    }

    /// Scan a folder for CSV files and import them
    func scanFolder(at folderURL: URL) async {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            errorMessage = "Could not read folder: \(folderURL.lastPathComponent)"
            return
        }

        let csvURLs = contents.filter { $0.pathExtension.lowercased() == "csv" }

        guard !csvURLs.isEmpty else {
            errorMessage = "No CSV files found in \(folderURL.lastPathComponent)"
            return
        }

        for url in csvURLs {
            await importFile(at: url)
        }
    }

    /// Clear import history
    func clearHistory() {
        importResults.removeAll()
        errorMessage = nil
    }
}
