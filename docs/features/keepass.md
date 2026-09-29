# KeePass

**Search KeePass** is a built-in command. It opens a native SwiftUI palette screen and reads a KDBX
through the installed KeePassXC application's `keepassxc-cli`. It needs neither the Raycast extension
nor JavaScript. KeePassXC remains a required external application; no library is bundled with Tinycast.

## Invariants

- Database access is read-only. The master password travels through stdin, never arguments or a shell.
- Decrypted exports, entries and master passwords are never written to disk, logs, backups or Keychain.
  The unlock form clears its password after submission, on dismissal and on lock. The reader releases
  its password when the operation ends; only decrypted entries remain for the unlocked session.
- Locking cancels an in-flight export and invalidates its result before clearing the entries. Unlock
  does not publish after a cancelled or superseded operation. This releases Swift values; it does not
  promise cryptographic zeroization of allocator memory.
- The configurable inactivity timeout defaults to five minutes; “Never” disables this timer.
  Search, selection, folder changes and entry actions restart it. Sleep, screen lock,
  session switching and quitting also lock it. Closing the palette clears unfinished credentials and
  cancels an unlock, but allows an already unlocked session to last until its inactivity timeout.
- Every copied field carries the concealed, transient and sensitive pasteboard markers. Copies clear
  after 30 seconds or on lock, only if the pasteboard still contains our write. New clipboard content
  is never cleared. Passwords and codes never enter Tinycast's clipboard history.
- No favicon requests or other network access. Opening an entry URL is an explicit action and accepts
  only HTTP and HTTPS.

## Using it

1. Run **Search KeePass** from the launcher (or bind it in Settings › Commands).
2. Choose a `.kdbx` database and enter its password. Actions › Choose Key File adds an optional
   key file. A blank password
   means key-file-only access, matching KeePassXC's `--no-password` mode.
3. Unlock. Search matches title, username, URL and group; all query words must match. The folder picker
   includes descendants. Pinned entries appear first and stay pinned per database.
4. Return pastes the password; Shift–Return pastes the username; Command–Return copies the password;
   Option–Return pastes a one-time code.
   Actions (Command–K or right-click) also offers username/URL/code copy and paste, Open URL and pinning.
5. Use Actions › Lock Database when finished. To refresh an externally edited database, lock and unlock it again.
   Actions › Change Database lets you choose another file, including while unlocked. Database actions
   remain available when the vault or search results are empty.
6. **Settings › KeePass** configures the database, optional key file, launch hotkey and auto-lock.
   **Actions › Auto-lock…** is also available both locked and unlocked. Pick **1 minute**, **5 minutes**
   (the default), **15 minutes**, **1 hour** or **Never**. Selecting a preset saves it and returns to
   the previous screen. Changes reset the timer immediately; Never cancels it. Sleep, screen lock,
   session switching and quitting still lock the database.

The unlock screen contains only the selected filename, password field and optional key filename.
Choose/Unlock and Actions use the palette's shared footer. The folder filter sits beside search in
its floating header; the unlocked list has no filename or Entries heading.

Passwords, key files and their combination are supported. Hardware challenge-response devices are not
supported by the unlock form. The database reader has a 30-second timeout and a 32 MB plaintext export
limit. An unavailable CLI, incorrect credentials, corrupt database or malformed export leaves the
screen locked with a retryable error.

CSV parsing preserves whitespace, Unicode, quoted commas, escaped quotes and multiline fields. The
extension's folder exclusions (`Deprecated`, `Recycle Bin`, `Trash`, `回收站`) are preserved. Passwords
and notes are not search terms. `{TITLE}`, `{USERNAME}`, `{PASSWORD}`, `{URL}`, `{NOTES}` and `{TOTP}`
field placeholders are expanded for copy/paste. One-time codes support the standard TOTP URI format,
SHA-1/256/512, 6–8 digits and configurable periods, checked against all RFC 6238 Appendix B vectors.

KeePass preserves the last external app across its own windows and file pickers. Pasting prefers the
currently active external app, then the palette's captured app, then the last external app. Tinycast
itself and terminated apps are excluded. Missing Accessibility permission is reported separately from
a missing target; enable it in System Settings › Privacy & Security › Accessibility.

## Keyboard shortcuts

Shortcuts appear beside their actions and work with the Actions menu open or closed. Entry actions
require a selected unlocked entry; database shortcuts also work with empty search results. Key-file
shortcuts are available on the unlock screen. Auto-lock's preset chooser uses Tab and Return.

| Action | Shortcut |
| --- | --- |
| Paste / copy password | Return / Command–Return |
| Paste / copy username | Shift–Return or Shift–Command–U / Command–U |
| Paste / copy one-time code | Option–Return / Shift–Command–T |
| Paste / copy URL | Shift–Command–Y / Command–Y |
| Open URL | Command–O |
| Pin / unpin entry | Command–Period |
| Change database | Shift–Command–O |
| Choose / remove key file | Shift–Command–F / Option–Shift–Command–F |
| Auto-lock presets | Shift–Command–L |
| Lock database | Command–L |

## Ownership and storage

`AppCore` owns `KeePassStore`, `KeePassClipboard` and `KeePassCoordinator`, starts its lock observers in
`start()` and stops it at termination. Views receive the coordinator through the palette environment.
`KeePassService` runs the native process off the main actor; the pure CSV/entry/TOTP models import no UI.

Only `keepassDatabasePath`, `keepassKeyFilePath`, `keepassAutoLockSeconds` (zero means Never)
and `keepassPinnedEntries` are saved in the current
bundle's UserDefaults domain. Pin identifiers are SHA-256 digests scoped to a database. This local
configuration stays out of settings backups. Dev and production remain isolated.

There is no automatic import of extension storage. Choose the database once in the native command and
unlock it there. The installed extension and its data are left alone; it can be removed in Settings ›
Extensions when no longer needed.

## Verification

`keepass-test` covers CSV edge cases, folder/search behavior, field substitution, TOTP vectors and
isolated persistence, saved timeout presets/defaults/Never, and paste-target selection across self/nil/terminated apps. `keepass-service-test` checks subprocess stdin, failures and cancellation, then
creates disposable KDBX fixtures with the installed CLI for password, key-file-only and combined
unlocking. Without KeePassXC, only the real-KDBX part is skipped. No personal vault is read by tests. `keepass-clipboard-test` verifies secret markers and conditional
clearing on a unique private pasteboard, never the system clipboard.
