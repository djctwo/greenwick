# Security Policy

## Reporting a vulnerability

Please report security problems privately through GitHub's private vulnerability
reporting: open the repository's **Security** tab and click **Report a vulnerability**
([direct link](https://github.com/djctwo/greenwick/security/advisories/new)). Do not open
a public issue for a security problem.

Include what you found, the steps or a small file that reproduces it, and the Greenwick
version (*Greenwick > About Greenwick*). Never include real trades, account numbers,
broker exports or API keys; a made-up example is enough. You will get an answer in the
advisory, and a fix is published as a new release.

## Supported versions

| Version | Supported |
| --- | --- |
| 1.x | Yes |
| Older | No |

## Security model

What Greenwick protects:

- **The journal on disk.** The database is always encrypted (AES-256-GCM). It is
  decrypted into memory only; no plaintext copy or write-ahead log is ever written. The
  journal and backups are created readable by your user account only.
- **The key.** With App Lock off, the journal key is stored in your macOS Keychain. With
  App Lock on, it is stored sealed with your password (PBKDF2-SHA256, 600,000 rounds), so
  the journal can't be decrypted without the password, even by someone who copies the
  files. Greenwick locks after the idle time you choose and when it goes to the
  background; if an unlock or an App Lock change is still running at that moment, it locks
  as soon as that finishes. App Lock steps run one at a time ("Forgot Password?" is
  unavailable until an unlock in progress finishes). Wrong passwords on the lock screen and
  in Settings (Change Password, Turn Off) share one limit: after five, Greenwick makes you
  wait, longer each time. A Keychain item that exists but can't be read keeps Greenwick
  locked and says so on the lock screen; it is never taken to mean that App Lock is off,
  and it never resets the wrong-password count or its wait (no password is checked until
  the item can be read). Erase All Local Data is refused while the keys can't be read.
- **Rollback.** Every save is numbered inside the encrypted file and in the Keychain. An
  older copy of the journal put back on disk is never opened silently. Each save is
  flushed to stable storage (`F_FULLFSYNC`) before its number is recorded, and a key
  change deletes the old key only after the re-encrypted file is on disk and reads back.
  Until then (for example on a full disk, or if Greenwick quits in the middle) the old key
  stays in the Keychain: after a password change it is wrapped with the new password;
  after turning App Lock on it is the plain lock-off key it was before, so until the next
  unlock finishes the change the journal is protected only as well as with App Lock off.
- **Backups.** Password-protected backups use AES-256-GCM with PBKDF2-SHA256 (600,000
  rounds). Every restore is validated (schema and every row) before anything is written.
- **Network.** Greenwick works offline. The optional AI analysis and quotes use your own
  API keys (kept in the Keychain), are off by default and use HTTPS with certificate
  pinning. AI analysis sends summary statistics, never individual trades, notes or
  account details. There is no telemetry.

What it does not protect against:

- **A running, unlocked Greenwick.** While the journal is unlocked it is decrypted in
  memory. Malware running as your user, or anyone using your unlocked Mac, can see it.
  Lock Greenwick (or turn on App Lock with a short idle time) when you step away. If
  Greenwick can't save the journal when it locks (for example the disk is full), it keeps
  the journal decrypted in memory behind the lock screen so the unsaved changes aren't
  lost, saves it at the next unlock, and asks before quitting without them (if Greenwick
  locks while it asks, it doesn't quit).
- **App Lock off.** Without App Lock, anyone who can use your logged-in macOS account can
  open the journal, because the key is in your login Keychain.
- **Files outside the journal.** Trade screenshots are stored as plain image files.
  Backups without a password, and CSV and PDF exports, are not encrypted. Watchlist
  symbols, checklist rules and display settings are kept in Greenwick's ordinary
  preferences file.
- **Forgotten passwords.** In the unsigned release builds there is no password recovery:
  a forgotten App Lock password means erasing the local data (after Touch ID or your Mac
  password) and restoring a backup. A forgotten backup password means that backup can't
  be opened.
- **Unsigned builds.** Release builds are not signed with an Apple Developer ID or
  notarized, so macOS can't confirm who built them. Download Greenwick only from this
  repository's Releases page, compare the `.sha256` file published with each release, or
  build it from source.
