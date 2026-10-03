# 64Edit

**Public domain.**

**64Edit** is the external source editor for **[64Forth](https://github.com/Win32Forth/64Forth)**. As of 64Forth **1.5.2**, the in-app SZ-EDITOR (`Library/Editor`) is removed. Edit Forth sources in 64Edit; 64Forth keeps the Console and App Output windows.

**Version lockstep:** 64Edit’s marketing version and build must match 64Forth. Current: **1.5.3** / build **47**.

Shipped beside **64Forth** in the dual-app DMG (from **1.5.2**). Drag **both** apps into `/Applications` (or keep them in the same folder). Gatekeeper Open Anyway applies once per app.

## How it connects

No special pairing after install. Both apps use the same Application Support paths:

1. Launch **64Forth** (it listens on a Unix domain socket).
2. Launch **64Edit**, or let 64Forth open it via `EDIT` / `VIEW` / DEBUG pause.
3. 64Edit connects to:

```text
~/Library/Application Support/64Forth/edit.sock
```

If 64Forth is not running, 64Edit reports that the socket is missing. Start 64Forth, then use Ping (reconnect only) or relaunch 64Edit.

**Launch path:** 64Forth finds `64Edit.app` as a **sibling** of `64Forth.app`, or at `/Applications/64Edit.app`. Debug developer builds prefer Xcode DerivedData first. Socket IPC works regardless of where the apps live. When 64Edit is already connected on `edit.sock`, 64Forth skips `/usr/bin/open -a` so the window does not flash/reactivate.

Shared IPC types live in `64Edit/IPCProtocol.swift` (mirrored on the 64Forth side as `App/IPCProtocol.swift`).

## EDIT, VIEW, and DEBUG from 64Forth

64Forth opens files with a small side channel (not XPC yet):

```text
~/Library/Application Support/64Forth/pending-goto.json
```

plus a wake-up DistributedNotification `com.Win32Forth.64Edit.goto`, and `open -a` only when no sock client is connected. Always consume the JSON file; notification `userInfo` is not reliable across processes. DEBUG pauses also send sock `debugLocation(path:line:)` so an already-running 64Edit can switch tabs without another launch.

| From 64Forth | pending-goto | 64Edit behavior |
|--------------|--------------|-----------------|
| `EDIT` path  | `mode: "edit"`, optional no line | Opens editable |
| `VIEW` / `EDIT-AT` / DEBUG pause | `mode: "view"`, `line` | Scrolls to the line; **View mode** (read-only) |

**View mode:** yellow banner, `NSTextView` not editable. Typing (or cut/paste/undo) asks **Switch to Edit mode?** Yes/No. Banner **Edit** or ⌘⇧E also unlocks editing. Each tab keeps its own view mode so debug-opened files stay browse until you unlock them. Path matching uses standardized paths, then same-inode / `fileResourceIdentifier`.

## Workspace

Single `Window("64Edit")` with tabs (not DocumentGroup):

- Open / Save / Save As / Close Tab; dirty mark `•` in the tab title
- Shared Forth console over `edit.sock` (resizable splitter; `consolePaneHeight`)
- Pending-goto and `debugLocation` find-or-open by path/inode; nested DEBUG steps open multiple files and restore the prior tab when stepping out
- Per-tab caret and top visible line on tab switch
- **Debug toolbar** while 64Forth ITC DEBUG/TDBG is armed: Step Over / Into / Out / Continue / Stop
  - While armed the Forth command field is **disabled** (execute is busy at pause) and focus moves to the editor so keys are not trapped in the console
  - Shortcuts: **F6** over, **F7** into, **F8** out, **F5** / **⌘⇧Y** continue, **Esc** stop
  - In browse (view) mode, Forth letter keys also work (`Space`/`o` over, `i` into, `g` continue, `q` stop)
  - Editor owns those keys when the NSTextView is first responder; `DebugKeyMonitor` handles them only when focus is elsewhere (both must not handle the same key)
  - After Continue/`g`, status shows Engine connected alone (late “debugger not armed” sock errors are ignored for the red banner)
- **View → Browse Mode** (⌘⇧B) toggles the selected tab between browse (read-only) and Allow Editing (merged into the system View menu)
- Ping reconnects the socket only (never evaluates Forth / WORDS)

Still ahead: highlight the current debug word, dirty-close prompts, polished New/untitled, splits, session restore, breakpoints, deeper XPC.

## Build

Open `64Edit.xcodeproj` in Xcode and run the **64Edit** scheme (Debug or Release) on macOS. Run `xcodebuild` from this project directory.

With Command Line Tools as the default `xcode-select`, set:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

before `xcodebuild` (or use full Xcode). For a DMG, build **Release** and place the app next to Release `64Forth.app`.

## Layout

```text
64Edit/
  64Edit.xcodeproj/
  64Edit/
    SixtyFourEditApp.swift   App entry (single Window workspace)
    AppDelegate.swift        open -a / Finder file opens → tabs
    WorkspaceModel.swift     Tab list, open/save, pending-goto find-or-open
    SixtyFourDocument.swift  UTType / FileDocument helpers
    ContentView.swift        Tabs + editor + shared console + DebugToolbar
    EditorTextView.swift     NSTextView; goto scroll; view-mode guard; DEBUG keys
    DebugKeyMonitor.swift    Window-level F5–F8 / letters when editor not focused
    PendingGoto.swift        pending-goto.json consume + scroll
    FileMenuFixup.swift
    ForthConnectionManager.swift
    IPCProtocol.swift
    Info.plist
    Assets.xcassets/
```

## Status

Usable companion for 64Forth **1.5.3** (version lockstep): tabs, view mode, DEBUG multi-file follow, sock steppers, Browse Mode, quiet opens when sock live. Leave `xcuserdata` unstaged when committing.
