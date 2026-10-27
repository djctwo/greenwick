import AppKit
import Foundation
import os

/// "Lock after inactivity" setting: Off or a number of minutes, 15 by default (also for
/// people who turned App Lock on before this setting existed)
enum IdleLockSetting {
    /// UserDefaults key (minutes; 0 = Off)
    static let key = "idleLockMinutes"
    static let choices = [0, 1, 5, 15, 30, 60]
    static let defaultMinutes = 15

    /// The chosen minutes; anything missing or not one of `choices` means the default
    static func minutes(in defaults: UserDefaults = .standard) -> Int {
        guard let stored = defaults.object(forKey: key) as? Int, choices.contains(stored) else {
            return defaultMinutes
        }
        return stored
    }

    /// Seconds without activity before locking; nil when Off
    static func timeout(in defaults: UserDefaults = .standard) -> TimeInterval? {
        let chosen = minutes(in: defaults)
        return chosen == 0 ? nil : TimeInterval(chosen * 60)
    }

    static func label(for minutes: Int) -> String {
        switch minutes {
        case 0: "Off"
        case 1: "1 minute"
        default: "\(minutes) minutes"
        }
    }
}

/// Locks the app after a stretch without keyboard or mouse activity in it.
///
/// Activity is the time of the last key or mouse event the app received (`NSEvent` local
/// monitor). A timer calls `check()`, which locks once the configured time has passed. While
/// not armed (App Lock off, or already locked) the countdown restarts, so it always begins
/// fresh after an unlock. The timer runs in the run loop's common modes, so modal alerts,
/// panels and menu/scroll tracking don't pause it. The clock is injectable for tests.
@MainActor
final class IdleLockMonitor {
    private let now: () -> Date
    private let timeout: () -> TimeInterval?
    private let isArmed: () -> Bool
    private let onIdle: () -> Void
    private(set) var lastActivity: Date
    private var eventMonitor: Any?
    private var timer: Timer?
    private static let logger = Logger(subsystem: "com.greenwick", category: "AppState")

    /// Events that count as activity
    static let activityEvents: NSEvent.EventTypeMask = [
        .keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel,
    ]

    /// - Parameters:
    ///   - timeout: seconds without activity before locking; nil = Off
    ///   - isArmed: whether locking applies now (App Lock on and not already locked)
    ///   - onIdle: locks the app (the normal lock path)
    init(now: @escaping () -> Date = Date.init,
         timeout: @escaping () -> TimeInterval?,
         isArmed: @escaping () -> Bool,
         onIdle: @escaping () -> Void) {
        self.now = now
        self.timeout = timeout
        self.isArmed = isArmed
        self.onIdle = onIdle
        self.lastActivity = now()
    }

    /// A key or mouse event happened
    func recordActivity() {
        lastActivity = now()
    }

    /// Lock if the time without activity has reached the setting. Returns whether it locked.
    @discardableResult
    func check() -> Bool {
        guard isArmed(), let limit = timeout() else {
            lastActivity = now()
            return false
        }
        guard now().timeIntervalSince(lastActivity) >= limit else { return false }
        Self.logger.notice("App Lock: locked after \(Int(limit / 60)) min without activity")
        lastActivity = now()
        onIdle()
        return true
    }

    /// Watch the app's key and mouse events and check every `interval` seconds
    func start(checkingEvery interval: TimeInterval = 5) {
        stop()
        lastActivity = now()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.activityEvents) { [weak self] event in
            MainActor.assumeIsolated { self?.recordActivity() }
            return event
        }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.check() }
        }
        // Common modes, not just the default one: the check must also run while a modal
        // alert or panel is up, or during menu and scroll tracking (else it fails open)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        timer?.invalidate()
        timer = nil
    }
}
