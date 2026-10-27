# Greenwick (open-source edition)

Native macOS trading journal for stock and day traders. Swift 6 (strict concurrency),
SwiftUI, GRDB (SQLite), Swift Charts, macOS 14+. GPL-3.0, © 2026 Douglas Cleary.
The stock-market sibling of Dojix (forex journal).

## Hard rules (this file is public — keep it free of private notes)
- **No secrets.** No API keys, tokens, certificates or signing identities in the repo.
  Optional services (Anthropic, Finnhub) use a key the *user* enters; it lives in their
  Keychain. Nothing may ever bill the maintainer.
- **No billing code.** No paywalls, tiers, trials, license keys, checkout or
  "upgrade" UI. Every feature is free.
- **No real data.** Sample files in `TestData/` and the demo generator are invented.
  Never add real trades, account numbers, broker exports, names or home-folder paths.
- **Opt-in network only.** AI analysis is off by default, needs the user's own key and
  an explicit switch in Settings, and sends summary statistics only (see
  `Configuration.AI.dataSentDescription` and `PromptBuilder`). No telemetry.
- **No code merged from outside contributors** (single copyright holder; see CONTRIBUTING.md).
- **Never run a build with the release bundle ID on a machine where Greenwick is
  installed for real use.** Use `GREENWICK_BUNDLE_ID=com.greenwick.app.test`
  (below). Data folder and Keychain service follow the bundle ID (`App/AppPaths.swift`).

## Layout
- `project.yml` — XcodeGen spec (the `.xcodeproj` is generated, not committed).
  Schemes: `Greenwick` (app + all tests), `GreenwickUnitTests` (unit tests only).
- `StockJournal/` — app sources (folder name predates the rename).
  `Services/Import/GenericCSVParser.swift` = all 11 broker parsers + FIFO pairing.
- `GreenwickTests/` — unit tests (parsers, headline stats, hostile input, storage, privacy).
- `GreenwickUITests/` — XCUITest suite. Each test launches the app with its own
  `GREENWICK_DATA_DIR` (under `GREENWICK_UITEST_ROOT`, else /tmp — never inside the test
  runner's container, which triggers macOS "access data from other apps" prompts) and its
  own `GREENWICK_KEYCHAIN_SERVICE` (Debug builds only; Release ignores both). Launch flags:
  `--uitesting` skips the welcome screen, `--uitesting-first-launch` shows it again; put
  them after any `-key value` defaults arguments (AppKit would read the next argument as
  the flag's value). Runs in CI (`ui-tests` job), which uploads screenshots of every
  screen; don't run it on a Mac with a real Greenwick install.
- `TestData/` — fictional sample exports, one per supported format.

## Run / test
```bash
brew install xcodegen
xcodegen generate
# Unit tests (throwaway bundle ID → separate data folder and Keychain entries)
xcodebuild test -project Greenwick.xcodeproj -scheme GreenwickUnitTests \
  -destination 'platform=macOS' GREENWICK_BUNDLE_ID=com.greenwick.app.test
# UI tests (needs a logged-in GUI session; normally left to CI)
TEST_RUNNER_GREENWICK_UITEST_ROOT=/tmp/greenwick-ui \
xcodebuild test -project Greenwick.xcodeproj -scheme Greenwick \
  -only-testing:GreenwickUITests GREENWICK_BUNDLE_ID=com.greenwick.app.test
# Release build
xcodebuild build -project Greenwick.xcodeproj -scheme Greenwick -configuration Release \
  GREENWICK_BUNDLE_ID=com.greenwick.app.test
```
- `GREENWICK_DATA_DIR=/some/folder` puts the database and screenshots elsewhere (Debug builds).
- Unit tests create Keychain items under the test service (journal key). Pass a fresh
  `TEST_RUNNER_GREENWICK_KEYCHAIN_SERVICE` per ad-hoc rebuild to avoid Keychain prompts,
  and delete those items afterwards.
- Live TLS pin check: run unit tests with `TEST_RUNNER_GREENWICK_NETWORK_TESTS=1`.
- Clean up after a test bundle ID: `~/Library/Application Support/Greenwick-<id>/`,
  `~/Library/Preferences/<id>.plist`, Keychain items with service `<id>` (UI tests:
  services `greenwick-uitests.*`, data under `<UITEST_ROOT>/greenwick-uitests/`).

## Notes
- Certificate pinning (`Services/Security/CertificatePinning.swift`) pins Google Trust
  Services CA keys for `api.anthropic.com` and `finnhub.io`. If either service changes CA,
  update the pins (the network test above will fail first).
- Import ticket IDs are content hashes (`TicketKeyCounter`), so re-importing a file skips
  trades that are already there.
- The journal is never plaintext on disk: `DatabaseManager` decrypts it into an in-memory
  SQLite database (`sqlite3_deserialize`) and after every commit (`JournalPersistence`)
  seals the whole database (AES-256-GCM) and writes it atomically. A plaintext file found
  at launch (older version) is encrypted at once. Backup export snapshots memory; restore goes through
  `BackupValidator` (schema must equal the migrator's, every row through
  `Trade.storageViolations`) and writes only the validated rows; never page-copies a backup.
- Keys: `AppLockVault`. Lock off = plain Keychain item `database_encryption_key`. Lock on =
  `database_key_wrapped` (sealed with PBKDF2-SHA256 600k of the password) + a
  `.userPresence` data-protection-Keychain copy for "Forgot password?" (needs a signed
  build; ad-hoc builds get "erase all local data" instead, which first needs Touch ID or
  the Mac password via `DeviceOwnerCheck`; tests inject `MemoryOwnerCheck`, never the
  real prompt). Turning the lock on and
  changing its password rotate to a new key in three crash-safe steps (`beginRotation`,
  `DatabaseManager.rekey`, `commitRotation`; unlock falls back to the old key and finishes).
  Never generate a key over an existing encrypted journal. Unlock, Forgot Password
  (recovery / erase), enable, change password and Turn Off all run through ONE gate,
  `AppState.performKeyOperation` (main actor, one at a time; another throws `busy`; the lock
  screen disables its buttons while `isKeyOperationRunning`). `lock()` during an operation
  sets `isLockRequested` and locks when it ends. After every `await` the code still
  re-checks its state (`isLocked`; `rotateKey` and Turn Off check that the journal they
  started with is still open, since quitting can close it). `rotateKey`
  (`AppState+KeyChange.swift`) deletes old keys only after the re-sealed file reads back
  with the new key, and once step 1 is stored never reports failure
  (`KeyChange.finishesAtNextUnlock`: the new password is in force). `rekey` throws on a
  closed or in-memory journal. Unlock with no lock left in the Keychain opens like a
  lock-off launch (and leaves the wrong-password count alone; a correct password resets it
  in `AppState.unlock`), except while a journal is held (`heldJournal`): then it stays
  locked (`keychainUnreadable`). `isAppLockEnabled` is in-memory state set by these
  operations, never re-read to decide whether to lock. Races are tested deterministically via
  `AppState.hooks` (`whileUnlocking` / `whileRotationBegins` run while the off-main step runs).
- Keychain reads: `SecretStore.lookup` returns `.found` / `.absent` (errSecItemNotFound
  only) / `.failed(status)`. Lock state and key creation decide on `lookup` and fail closed:
  an unreadable lock item = locked (`keychainUnreadable` at unlock), an unreadable plain key
  is never replaced. `UnlockThrottle` reads its count and wait with `lookup` too: a read
  error refuses every password check (`keychainUnreadable`) and the count is never
  rewritten. A lock item unreadable at launch sets `AppState.keychainUnreadableAtLaunch`
  (the lock screen says so at once, even with App Lock off). Erase refuses while a key item
  reads `.failed`, then deletes `Greenwick.sqlite` by path and checks it is gone before
  removing any key (`journalNotDeleted`).
- The recovery copy's key fingerprint (`database_key_recovery_fingerprint`) lets unlock
  replace an outdated copy; recovery with an outdated copy throws `recoveryKeyOutdated` and
  the lock screen offers erase. Wrong passwords: `UnlockThrottle` (Keychain, on
  `AppLockVault.throttle`), shared by the lock screen and Settings' Change Password / Turn Off.
- Release builds ignore `GREENWICK_DATA_DIR` / `GREENWICK_KEYCHAIN_SERVICE` (Debug only)
  and are signed without `get-task-allow`.
- Every stored trade passes `Trade.sanitizedForStorage()` (limits in `TradeLimits`);
  Double→Int conversions on trade data use `Int(saturating:)`.
- Anything describing the user's account (e.g. `PropFirmSettings`) goes in the journal's
  `settings` table, never UserDefaults (readable while locked). Failed journal saves post
  `.journalSaveFailed` (shown as the "Database Issue" alert). The migrator never erases a
  database (no `eraseDatabaseOnSchemaChange`, not even in Debug). Keychain writes update in
  place (never delete-then-add). Backup schema checks use `PRAGMA table_xinfo`.
- The sealed journal and backup exports are written with `SecureFileWriter` (random temp
  name, `O_CREAT|O_EXCL|O_NOFOLLOW` 0600, fchmod + `F_FULLFSYNC` on the descriptor, `rename`,
  then the folder is flushed; never reopened or chmod'ed by path). Tests inject journal
  write failures through `JournalFileWriter` (`AppState(journalWriter:)`).
- Opening: only a file that fails to decrypt (`DatabaseManager.isUnreadable`) is set aside
  as `.unreadable-<date>`; any other error (disk, permissions) leaves it untouched with a
  message. The save made while opening is non-fatal (journal stays open in memory, reported
  as a save failure). Closing makes the final save and marks the journal closed in one
  writer-queue turn; off-main writes (restore) call `checkOpen()` inside their write. If the
  final save fails the journal stays open: a lock keeps it decrypted in memory behind the
  lock screen (`AppState.heldJournal`) and unlock puts it back and saves again; quitting
  asks first (`AppDelegate.replyToQuit` → `AppState.saveBeforeQuit`, Try Again / Quit
  Anyway; an alert ended without a choice, e.g. by a lock's `abortModal`, cancels the
  quit). Only `DatabaseManager.close()` (quit, erase) drops unsaved changes.
- One running copy per data folder: `InstanceLock` holds `flock(LOCK_EX|LOCK_NB)` on
  `Greenwick.lock` for the process lifetime; a second copy sets
  `AppState.isAnotherCopyRunning`, opens nothing and shows `AlreadyOpenView`. It fails open
  (`.unavailable`) where the folder has no file locks (some network/FUSE volumes); the docs
  say so.
- Journal file format (`JournalFormat`, v2): "GWJN" | version | 16-byte random epoch |
  generation | saved-at ms, all AES-GCM associated data. Every save is generation + 1; then
  the stamp + SHA-256 of the file go to the Keychain (`JournalLedger`, account
  `journal_generation`, kept on `AppLockVault.ledger`; tests use a `MemorySecretStore`). On
  load (`JournalLedger.verdict`) a lower generation, another epoch, or an equal generation
  with another hash throws `DatabaseManager.OlderJournal` and the file is left untouched
  (`AppState.olderJournal`: lock on = lock screen asks for the password again; lock off =
  `OlderJournalView`). A confirmed open starts a NEW epoch at max(last, file) + 1; the
  counter never goes down. Files without a header (older versions) = generation 0. Keychain write failures are
  logged, never fatal. Erase All Local Data removes the record.
- Backups: `BackupEncryption` ("GWBK" v2: rounds + salt in the header = AES-GCM associated
  data, PBKDF2-SHA256 600k, reads refuse > 10,000,000 rounds; legacy "SJNL" 100k read-only).
  `BackupFlowModel` drives the Settings sheets; a protected backup asks for its password.
- Idle auto-lock: `IdleLockMonitor` (NSEvent local monitor + a timer in `.common` run-loop
  modes, injectable clock), setting `IdleLockSetting` (UserDefaults `idleLockMinutes`,
  default 15). `AppState.lock()` also ends any app-modal panel (`NSApp.abortModal`).
- GRDB is pinned by commit (`revision:` in project.yml; no Package.resolved is committed).
- Releases: pushing a tag `v<MARKETING_VERSION>` runs the `release` job in
  `.github/workflows/macos.yml`, which builds the unsigned Release app and attaches
  `Greenwick-macOS-unsigned.zip` (+ `.sha256`) to a GitHub Release (notes:
  `docs/release-notes/<tag>.md` if present).
