# xerminal for iPad — Project Plan

> Minimal, terminal-native SSH client for iPad. Termius feature-set, Kaku aesthetic. No local shell — SSH only.

---

## Stack

| Layer | Choice | Rationale |
|---|---|---|
| Language | Swift (native) | Best iPad keyboard/trackpad/Stage Manager support |
| UI framework | UIKit | Pixel-level control of terminal view; SwiftUI wrapping where useful |
| Terminal emulation | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | Production-proven (Secure Shellfish, La Terminal, CodeEdit). CoreText rendering, full Unicode/emoji, UIKit `TerminalView` ready to embed. iOS sample with SSH already exists. |
| SSH | [Citadel](https://github.com/orlandos-nl/Citadel) (over swift-nio-ssh) | High-level API atop Apple's NIOSSH. Handles RSA keys, legacy ciphers, OpenSSH key parsing, SFTP. Raw NIOSSH only supports modern primitives (Ed25519, ECDSA, AES-GCM) — many real servers still need RSA. |
| Key storage | iOS Keychain + Secure Enclave | SEP-bound keys never leave device |
| Config storage | JSON files in app container | Simple, inspectable, versionable |
| Sync | iCloud Key-Value Store | Lightweight host config sync; no server infra |

---

## Architecture

```
┌─────────────────────────────────────────────┐
│                  App Shell                   │
│  ┌─────────────────────────────────────────┐│
│  │          Tab Bar (native UIKit)         ││
│  ├─────────────────────────────────────────┤│
│  │                                         ││
│  │     SwiftTerm TerminalView              ││
│  ┌─────────────────────────────────────────┐│
│  │  TerminalTabBarView (custom UIView)    ││
│  │  [tab1] [tab2] [tab3]  [+]            ││
│  │  (same monospace font/colors as term)  ││
│  ├─────────────────────────────────────────┤│
│  │                                         ││
│  │     SwiftTerm TerminalView              ││
│  │     (full-screen, per-tab)              ││
│  │                                         ││
│  │  ┌───────────────────────────────────┐  ││
│  │  │  SSH Session (Citadel/NIOSSH)     │  ││
│  │  │  ┌─────────┐  ┌───────────────┐  │  ││
│  │  │  │ PTY/Shell│  │ SFTP Channel  │  │  ││
│  │  │  └─────────┘  └───────────────┘  │  ││
│  │  └───────────────────────────────────┘  ││
│  └─────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────┐│
│  │  Host Manager / Settings (modal sheets) ││
│  └─────────────────────────────────────────┘│
└─────────────────────────────────────────────┘
```

**Key design decision:** The tab bar is a custom `TerminalTabBarView` — a UIView rendered with the same monospaced font, cell sizing, and color palette as the terminal. Visually it's part of the terminal grid; architecturally it's a separate view so it doesn't interfere with the PTY's row/col geometry. Settings and host management use native modal sheets.

---

## Phases

### Phase 0 — Scaffolding (3-5 days)

- Xcode project, SPM deps (SwiftTerm, Citadel, swift-nio-ssh)
- Single-window app with one embedded `TerminalView`
- Basic app lifecycle (background/foreground)
- Hardware keyboard responder chain setup — verify all modifier keys work with SwiftTerm's `TerminalView`
- Option-as-Meta toggle

**Exit criteria:** App launches, shows a blank terminal view, keyboard input is captured and echoed.

### Phase 1 — SSH Connect (1-2 weeks)

- `SSHSessionManager`: connect, authenticate, manage PTY channel
- Auth methods: password, key-based (ed25519, ECDSA, RSA via Citadel)
- Wire Citadel's SSH channel ↔ SwiftTerm's `TerminalView` via `TerminalViewDelegate`
- Known hosts: first-connect fingerprint prompt, persist to file
- Connection state handling: connecting / connected / disconnected / error
- Auto-reconnect on network change (NWPathMonitor)
- Terminal resize → SSH window-change message

**Exit criteria:** Can SSH into a real server, run commands, see output. Handles disconnect gracefully.

### Phase 2 — Host Management (1 week)

- Host model: label, hostname, port, username, auth method, key reference
- Host list screen (modal sheet, or a "new tab" landing page)
- Add / edit / delete hosts
- Quick-connect: type `user@host` in an input field
- Key management: generate ed25519/RSA keys, import from Files app, store in Keychain
- Export public key (share sheet)

**Exit criteria:** Can save hosts, pick from list to connect. Keys generated and stored.

### Phase 3 — Tabs (1.5-2 weeks)

The tab bar must be rendered in the terminal's visual language — same monospaced font, same color palette, same character-cell grid alignment. It should look like it's part of the terminal output, not a native UIKit control.

**Implementation: separate UIView, same visual language (not inside the PTY grid).** A custom `TerminalTabBarView` sits directly above the `TerminalView`, rendered with identical font metrics and cell sizing. This avoids corrupting the PTY's row/col geometry while being visually seamless.

- `TerminalTabBarView`: custom UIView, 1 row tall (matches terminal cell height)
  - Renders tab labels as attributed strings in the same monospaced font
  - Active tab: inverted colors (fg/bg swap) or underline/highlight
  - Inactive tabs: dimmed
  - Overflow: horizontal scroll or `…` truncation when tabs exceed width
  - Close button per tab: rendered as `×` character, click target
  - `+` button at end: new tab
- Each tab = one `TerminalView` + one SSH session (swapped in/out of the view hierarchy)
- Keyboard shortcuts:
  - `⌘T` — new tab (opens host picker)
  - `⌘W` — close tab (confirm if connected)
  - `⌘1-9` — switch to tab N
  - `⌘⇧[` / `⌘⇧]` — previous/next tab
  - `⌘N` — new window (Stage Manager)
- Tab title: auto from SSH hostname, editable via double-click/⌘R
- Tab state: connected (normal text) / disconnected (strikethrough or red tint)
- Visual continuity: tab bar background = terminal background, no border/separator — just a continuous character grid

**Exit criteria:** Multi-tab SSH sessions, tab bar is visually indistinguishable from terminal content, full keyboard-driven tab management.

### Phase 4 — SFTP (1-2 weeks)

- SFTP channel via Citadel (runs over existing SSH connection)
- TUI-style file browser in a dedicated tab/panel:
  - Navigate with arrow keys, enter to open dir
  - `d` download, `u` upload, `r` rename, `x` delete
- Upload: pick from Files app (UIDocumentPickerViewController)
- Download: save to Files app
- Transfer progress indicator

**Exit criteria:** Can browse remote filesystem, upload/download files.

### Phase 5 — Port Forwarding (3-5 days)

- Local port forwarding (`-L`)
- Remote port forwarding (`-R`)
- Dynamic/SOCKS (`-D`)
- Config per host (saved with host definition)
- Active forwarding indicator in tab bar or status area

**Exit criteria:** Port forwarding works, persists across sessions.

### Phase 6 — Terminal Customization (3-5 days)

- Theme system: background, foreground, ANSI 16 colors, cursor color
- Ship 5-8 themes (Kaku-dark, Solarized Dark, Dracula, Nord, Kanagawa, One Dark, Gruvbox, Tokyo Night)
- Font picker: system monospace + bundled (JetBrains Mono, Fira Code, Meslo)
- Font size slider
- Cursor style: block / underline / bar, blinking toggle
- Per-host theme override

**Exit criteria:** Themes and fonts apply correctly, persist.

### Phase 7 — Polish & iPad-native (1 week)

- Touch/Face ID app lock
- Stage Manager / multi-window (UIScene)
- Trackpad/pointer: hover states, right-click context menu in terminal
- Spotlight integration: index saved hosts, quick-connect
- Shortcuts app: "Connect to [host]" action
- Session persistence: reconnect on app foreground
- Haptic feedback on key events (subtle, optional)

**Exit criteria:** Feels like a native iPad app, not a ported one.

### Phase 8 — Ship (3-5 days)

- TestFlight beta
- App Store review prep (terminal/SSH apps are approved — Termius, Blink, a-Shell precedent)
- Privacy policy, App Store listing
- Landing page

---

## v1.1 Roadmap (post-launch)

| Feature | Effort |
|---|---|
| Snippets (saved commands, tap to execute) | 3-5 days |
| Command history (unified across sessions) | 2-3 days |
| Split pane (vertical/horizontal within tab) | 1 week |
| Host groups/folders | 2-3 days |
| Mosh support | 1 week |
| Jump hosts / ProxyJump chains | 3-5 days |
| Session logging (auto-capture output) | 2-3 days |
| Command autocomplete | 1 week |

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Citadel missing cipher/algorithm for specific server | Can't connect to some hosts | Fall back to libssh2 wrapper if needed; file issues upstream |
| SwiftTerm keyboard edge cases on iPad | Broken modifier keys | SwiftTerm's iOS path is battle-tested (La Terminal); budget time for edge case fixes |
| App Store rejection | Can't ship | Precedent is strong (Termius, Blink). No local shell = no sandbox concerns. |
| SFTP performance | Slow transfers | Citadel claims improved SFTP perf; test with large files early |
| iCloud sync conflicts | Lost host configs | Last-write-wins is fine for v1; host configs are small/infrequent |

---

## Timeline Summary

| Phase | Duration | Cumulative |
|---|---|---|
| 0 — Scaffolding | 3-5 days | ~1 week |
| 1 — SSH Connect | 1-2 weeks | ~3 weeks |
| 2 — Host Management | 1 week | ~4 weeks |
| 3 — Tabs (TUI-rendered) | 1.5-2 weeks | ~6 weeks |
| 4 — SFTP | 1-2 weeks | ~8 weeks |
| 5 — Port Forwarding | 3-5 days | ~9 weeks |
| 6 — Terminal Customization | 3-5 days | ~10 weeks |
| 7 — Polish | 1 week | ~11 weeks |
| 8 — Ship | 3-5 days | ~11-12 weeks |

**Total: ~11-12 weeks** for a solo dev working full-time. Adjust for part-time accordingly.
