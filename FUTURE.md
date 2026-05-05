# Deferred features

Tracking items intentionally skipped from current scope.

## SFTP (was Phase 4)

TUI file browser via Citadel's SFTP channel over existing SSH. Skipped — not needed now.

- Dedicated browser tab or split panel
- Arrow-key nav, `d` download / `u` upload / `r` rename / `x` delete
- Files-app integration (`UIDocumentPickerViewController`)
- Transfer progress

## Smaller deferred items

- **Files-app key import** — paste-only today; add `UIDocumentPickerViewController` for `.pem` files.
- **Per-host known-hosts management** — list/remove individual entries. Today: Settings → Known Hosts shows count + "Clear All" only.
- **Tab title editing** — `⌘R` / double-click to rename. Auto-set to `user@host` for now.
- **Background-tab activity indicator** — dot/asterisk on inactive tabs receiving stdout.
- **Encrypted ECDSA keys** — current parser supports unencrypted only. Needs bcrypt+AES decryption (Citadel internals not exposed for ECDSA).
- **Disconnect/reconnect from tab bar** — currently silent close on `×`; consider explicit reconnect action for disconnected tabs.
- **Terminal scrollback wipe on reconnect** — keep or clear; tbd.
