import AppKit
import SwiftUI

/// Shown instead of the journal when another copy of Greenwick already has this Mac's journal
/// open (`InstanceLock`). Two copies would overwrite each other's saves, so this one opened
/// nothing and only offers to switch to the other copy or quit.
struct AlreadyOpenView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "macwindow.on.rectangle")
                .font(.kpiValue)
                .foregroundStyle(Color.textSecondary)

            Text("Greenwick is already open")
                .font(.kpiValueSecondary)
                .fontWeight(.bold)
                .accessibilityIdentifier("alreadyOpen.title")

            Text("Another copy of Greenwick is using your journal. Only one copy can have it open at a time, "
                 + "so this one opened nothing. Switch to the other copy, or quit it before opening Greenwick again.")
                .font(.bodyText)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                if let other = Self.otherCopy {
                    Button("Switch to It") {
                        other.activate()
                        NSApp.terminate(nil)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgContent)
        .preferredColorScheme(.dark)
    }

    /// The other running copy with this bundle ID (nil if it can't be found, e.g. `open -n`
    /// of a differently named build sharing the data folder)
    private static var otherCopy: NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != me }
    }
}
