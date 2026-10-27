import SwiftUI
import AppKit
import UniformTypeIdentifiers
import os

// MARK: - Trade Screenshots View

/// Horizontal thumbnail strip for managing trade screenshot attachments. Images are
/// encrypted on disk (`ScreenshotManager`) and decrypted into memory to display them.
struct TradeScreenshots: View {
    let trade: Trade
    @Environment(\.appState) private var appState
    @State private var screenshots: [String] = []
    @State private var selectedImage: NSImage?
    @State private var showingImageViewer = false

    private var manager: ScreenshotManager { appState.screenshots }
    private static let maxScreenshots = 10
    private static let logger = Logger(subsystem: "com.greenwick", category: "TradeScreenshots")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Screenshots", systemImage: "photo.on.rectangle.angled")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("\(screenshots.count)/\(Self.maxScreenshots)")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(screenshots, id: \.self) { filename in
                        thumbnailView(for: filename)
                    }
                    if screenshots.count < Self.maxScreenshots {
                        addButton
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 8))
        .onDrop(of: [.image, .fileURL], isTargeted: nil, perform: handleDrop)
        .onAppear { screenshots = trade.screenshotList }
        .sheet(isPresented: $showingImageViewer) {
            if let image = selectedImage {
                ImageViewerSheet(image: image)
            }
        }
    }

    // MARK: - Thumbnail

    private func thumbnailView(for filename: String) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = manager.loadImage(filename: filename, for: trade.id ?? 0) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.bgInset
                        .overlay { Image(systemName: "photo").foregroundStyle(Color.textTertiary) }
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderCard, lineWidth: 1)
            )
            .onTapGesture {
                selectedImage = manager.loadImage(filename: filename, for: trade.id ?? 0)
                showingImageViewer = selectedImage != nil
            }

            Button {
                deleteScreenshot(filename)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.bodyText)
                    .foregroundStyle(Color.textPrimary, Color.semanticRed)
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button(action: openFilePicker) {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: "plus")
                        .font(.kpiValueSecondary)
                        .foregroundStyle(Color.textSecondary)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }

        let remaining = Self.maxScreenshots - screenshots.count
        for url in panel.urls.prefix(remaining) {
            guard let image = NSImage(contentsOf: url) else { continue }
            addImage(image)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard screenshots.count < Self.maxScreenshots else { return false }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let urlData = data as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil),
                      UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true,
                      let image = NSImage(contentsOf: url) else { return }
                DispatchQueue.main.async { addImage(image) }
            }
        }
        return true
    }

    private func addImage(_ image: NSImage) {
        guard let tradeId = trade.id,
              screenshots.count < Self.maxScreenshots else { return }
        do {
            let filename = try manager.saveImage(image, for: tradeId)
            screenshots.append(filename)
            persistScreenshots(tradeId: tradeId)
        } catch {
            Self.logger.error("Failed to save screenshot: \(error.localizedDescription)")
        }
    }

    private func deleteScreenshot(_ filename: String) {
        guard let tradeId = trade.id else { return }
        do {
            try manager.deleteImage(filename: filename, for: tradeId)
        } catch {
            Self.logger.error("Failed to delete screenshot: \(error.localizedDescription)")
        }
        screenshots.removeAll { $0 == filename }
        persistScreenshots(tradeId: tradeId)
    }

    private func persistScreenshots(tradeId: Int64) {
        let joined = screenshots.joined(separator: ",")
        do {
            try appState.tradeRepository.updateScreenshots(tradeId: tradeId, screenshots: joined)
        } catch {
            Self.logger.error("Failed to persist screenshots: \(error.localizedDescription)")
        }
    }
}

// MARK: - Image Viewer Sheet

/// Full-size screenshot viewer presented as a sheet
struct ImageViewerSheet: View {
    let image: NSImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(12)

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 800, maxHeight: 600)
                .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(Color.bgCard)
    }
}
