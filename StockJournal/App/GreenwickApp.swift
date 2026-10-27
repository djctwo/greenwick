import Combine
import SwiftUI
import GRDB

/// App-level lifecycle: the journal is saved and closed when Greenwick quits, whatever
/// window is (or isn't) open (if it can't be saved, quitting asks first); idle auto-lock
/// runs for the whole app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Locks after the chosen minutes without keyboard or mouse activity (App Lock on)
    private var idleLock: IdleLockMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState.shared
        let monitor = IdleLockMonitor(
            timeout: { IdleLockSetting.timeout() },
            isArmed: { state.isAppLockEnabled && !state.isLocked },
            onIdle: { state.lock() })
        monitor.start()
        idleLock = monitor
    }

    /// Changes that couldn't be saved (e.g. a full disk) are never dropped without asking
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.replyToQuit(AppState.shared) { problem in
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Greenwick couldn't save your latest changes"
            alert.informativeText = "Saving failed (\(problem)). If you quit now, the changes since the last successful save are "
                + "lost. Free up disk space or check access to the Greenwick folder, then click Try Again."
            alert.addButton(withTitle: "Try Again")
            alert.addButton(withTitle: "Quit Anyway")
            return alert.runModal()
        }
    }

    /// Quit only when everything is saved or the owner chose Quit Anyway. `ask` shows the
    /// Try Again / Quit Anyway alert for the save problem and returns the response.
    static func replyToQuit(_ state: AppState,
                            ask: (String) -> NSApplication.ModalResponse) -> NSApplication.TerminateReply {
        while let problem = state.saveBeforeQuit() {
            switch ask(problem) {
            case .alertFirstButtonReturn:
                continue // Try Again
            case .alertSecondButtonReturn:
                return .terminateNow // Quit Anyway
            default:
                // Ended without a choice (a lock closes the alert with `abortModal`): don't
                // quit. The changes stay in memory (behind the lock screen); the next quit
                // asks again.
                return .terminateCancel
            }
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        idleLock?.stop()
        AppState.shared.shutdown()
    }
}

@main
struct GreenwickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared
    @AppStorage("onboarding_complete") private var onboardingComplete = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // UI tests: `--uitesting-first-launch` starts as if Greenwick had never been opened,
        // so the welcome screen shows again. (`--uitesting` skips it instead.)
        if CommandLine.arguments.contains("--uitesting-first-launch") {
            UserDefaults.standard.removeObject(forKey: "onboarding_complete")
        }
        KeychainHelper.migrateFromUserDefaults()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isAnotherCopyRunning {
                    AlreadyOpenView()
                } else if appState.isLocked {
                    LockScreenView()
                } else if let older = appState.olderJournal {
                    OlderJournalView(older: older)
                } else if appState.isDatabaseFailed {
                    DatabaseFailedView(errorMessage: appState.databaseError ?? "Unknown error")
                } else if !onboardingComplete && !CommandLine.arguments.contains("--uitesting") {
                    OnboardingView(isFirstTime: true)
                } else {
                    ContentView()
                        .id(ObjectIdentifier(appState.database)) // fresh view models for a reopened journal
                        .frame(minWidth: 900, minHeight: 600)
                        .alert("Database Issue", isPresented: .init(
                            get: { appState.databaseError != nil && !appState.isDatabaseFailed },
                            set: { if !$0 { appState.databaseError = nil } }
                        )) {
                            Button("OK", role: .cancel) { }
                        } message: {
                            Text(appState.databaseError ?? "")
                        }
                }
            }
            .environment(\.appState, appState)
            .onReceive(NotificationCenter.default.publisher(for: .journalSaveFailed).receive(on: RunLoop.main)) { note in
                appState.reportSaveFailure(note.userInfo?[DatabaseManager.saveErrorKey] as? String)
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Auto-lock: closes the journal and forgets its key until the password is entered
                if newPhase == .background {
                    appState.lock()
                }
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .sidebar) {
                Button("Show Journal") {
                    appState.selectedTab = .journal
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Show Dashboard") {
                    appState.selectedTab = .dashboard
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Show Analytics") {
                    appState.selectedTab = .analytics
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Show Edge Report") {
                    appState.selectedTab = .edgeReport
                }
                .keyboardShortcut("4", modifiers: .command)

                Button("Show Import") {
                    appState.selectedTab = .importTrades
                }
                .keyboardShortcut("5", modifiers: .command)

                Button("Show Settings") {
                    appState.selectedTab = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .newItem) {
                Button("New Trade") {
                    appState.selectedTab = .journal
                    NotificationCenter.default.post(name: .showAddTrade, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Import Trades...") {
                    appState.selectedTab = .importTrades
                }
                .keyboardShortcut("i", modifiers: .command)
            }

            CommandGroup(replacing: .help) {
                Button("Greenwick Help") {
                    openHelpWindow()
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        Window("About Greenwick", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Window("Greenwick Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 900, height: 600)
    }

    @Environment(\.openWindow) private var openWindow

    private func openHelpWindow() {
        openWindow(id: "help")
    }
}
