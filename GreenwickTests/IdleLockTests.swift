import XCTest
@testable import Greenwick

/// Idle auto-lock: with App Lock on, Greenwick locks after the chosen minutes without
/// keyboard or mouse activity in the app (default 15, Off possible). Driven by an
/// injected clock; the app's timer only calls `check()`.
final class IdleLockTests: XCTestCase {

    /// A clock the test moves by hand
    @MainActor
    final class TestClock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(minutes: Double) { now = now.addingTimeInterval(minutes * 60) }
    }

    @MainActor
    private func makeMonitor(clock: TestClock, minutes: Int?, armed: @escaping () -> Bool = { true },
                             onIdle: @escaping () -> Void) -> IdleLockMonitor {
        IdleLockMonitor(now: { clock.now },
                        timeout: { minutes.map { TimeInterval($0 * 60) } },
                        isArmed: armed,
                        onIdle: onIdle)
    }

    @MainActor
    func testLocksAtTheThresholdAndNotBefore() {
        let clock = TestClock()
        var locks = 0
        let monitor = makeMonitor(clock: clock, minutes: 15) { locks += 1 }
        clock.advance(minutes: 14.99)
        XCTAssertFalse(monitor.check())
        XCTAssertEqual(locks, 0, "Not before 15 minutes")
        clock.advance(minutes: 0.01)
        XCTAssertTrue(monitor.check(), "At 15 minutes exactly")
        XCTAssertEqual(locks, 1)
    }

    @MainActor
    func testActivityRestartsTheCountdown() {
        let clock = TestClock()
        var locks = 0
        let monitor = makeMonitor(clock: clock, minutes: 5) { locks += 1 }
        clock.advance(minutes: 4)
        monitor.recordActivity()
        clock.advance(minutes: 4)
        XCTAssertFalse(monitor.check(), "Only 4 minutes since the last key or mouse event")
        clock.advance(minutes: 1)
        XCTAssertTrue(monitor.check())
        XCTAssertEqual(locks, 1)
    }

    @MainActor
    func testOffNeverLocks() {
        let clock = TestClock()
        var locks = 0
        let monitor = makeMonitor(clock: clock, minutes: nil) { locks += 1 }
        clock.advance(minutes: 24 * 60)
        XCTAssertFalse(monitor.check())
        XCTAssertEqual(locks, 0)
    }

    /// App Lock off (or already locked): nothing happens, and the countdown starts fresh
    /// once it applies again (so an unlock never locks again at once)
    @MainActor
    func testNotArmedDoesNothingAndRestartsTheCountdown() {
        let clock = TestClock()
        var locks = 0
        var armed = false
        let monitor = makeMonitor(clock: clock, minutes: 1, armed: { armed }) { locks += 1 }
        clock.advance(minutes: 30)
        XCTAssertFalse(monitor.check())
        armed = true
        clock.advance(minutes: 0.5)
        XCTAssertFalse(monitor.check(), "Counted from when it was last checked unarmed")
        clock.advance(minutes: 0.5)
        XCTAssertTrue(monitor.check())
        XCTAssertEqual(locks, 1)
    }

    /// The check must keep running while a modal alert/panel or a menu/scroll tracking loop
    /// has the run loop (a timer in the default mode only would never fire then, and an
    /// alert left open would keep the app unlocked forever)
    @MainActor
    func testTimerKeepsCheckingDuringModalAndTrackingLoops() {
        for mode in [RunLoop.Mode.modalPanel, .eventTracking] {
            let clock = TestClock()
            var locks = 0
            let monitor = makeMonitor(clock: clock, minutes: 1) { locks += 1 }
            monitor.start(checkingEvery: 0.05)
            clock.advance(minutes: 2)
            let deadline = Date().addingTimeInterval(2)
            while locks == 0, Date() < deadline {
                RunLoop.main.run(mode: mode, before: Date().addingTimeInterval(0.05))
            }
            monitor.stop()
            XCTAssertEqual(locks, 1, "Idle check must fire in \(mode.rawValue)")
        }
    }

    func testSettingDefaultsTo15MinutesWithOffAndTheChoices() throws {
        let suite = "gw-idle-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }

        XCTAssertEqual(IdleLockSetting.choices, [0, 1, 5, 15, 30, 60])
        XCTAssertEqual(IdleLockSetting.minutes(in: defaults), 15, "New and existing users: 15 minutes")
        XCTAssertEqual(IdleLockSetting.timeout(in: defaults), 900)
        defaults.set(0, forKey: IdleLockSetting.key)
        XCTAssertNil(IdleLockSetting.timeout(in: defaults), "Off")
        defaults.set(60, forKey: IdleLockSetting.key)
        XCTAssertEqual(IdleLockSetting.timeout(in: defaults), 3600)
        defaults.set(7, forKey: IdleLockSetting.key)
        XCTAssertEqual(IdleLockSetting.minutes(in: defaults), 15, "Unknown values fall back to the default")
        XCTAssertEqual(IdleLockSetting.label(for: 0), "Off")
        XCTAssertEqual(IdleLockSetting.label(for: 1), "1 minute")
        XCTAssertEqual(IdleLockSetting.label(for: 30), "30 minutes")
    }

    /// The real lock path: wired as in the app, an idle timeout closes the journal and
    /// forgets its key, and the password opens it again
    @MainActor
    func testIdleTimeoutLocksTheAppThroughTheNormalLockPath() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = AppState(vault: vault, databasePath: folder.appendingPathComponent("Greenwick.sqlite").path,
                             screenshotsDirectory: folder.appendingPathComponent("Screenshots", isDirectory: true))
        _ = try state.tradeRepository.bulkInsert(sampleTrades())
        let clock = TestClock()
        let monitor = IdleLockMonitor(now: { clock.now }, timeout: { 15 * 60 },
                                      isArmed: { state.isAppLockEnabled && !state.isLocked },
                                      onIdle: { state.lock() })

        clock.advance(minutes: 20)
        XCTAssertFalse(monitor.check(), "App Lock off: never")
        XCTAssertFalse(state.isLocked)

        _ = try await state.enableAppLock(password: "correct-horse-42")
        clock.advance(minutes: 14)
        XCTAssertFalse(monitor.check())
        clock.advance(minutes: 1)
        XCTAssertTrue(monitor.check())
        XCTAssertTrue(state.isLocked)
        for _ in 0..<20 where state.database.isPersistent { await Task.yield() }
        XCTAssertFalse(state.database.isPersistent, "Saved and closed")
        XCTAssertNil(state.database.encryptionKey, "Key forgotten")

        clock.advance(minutes: 60)
        XCTAssertFalse(monitor.check(), "Already locked")
        let unlocked = await state.unlock(password: "correct-horse-42")
        XCTAssertEqual(unlocked, .unlocked)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
        state.shutdown()
    }
}
