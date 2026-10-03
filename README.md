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

**View mode:** yellow banner, `NSTextView` not editable. Typing, cut, paste, and undo are ignored (no dialog). Banner **Edit**, ⌘⇧E, or **View → Allow Editing** unlocks editing. Each tab keeps its own view mode so debug-opened files stay browse until you unlock them. Path matching uses standardized paths, then same-inode / `fileResourceIdentifier`.

## Workspace

Single `Window("64Edit")` with tabs (not DocumentGroup):

- **New File** (`⌘N`): Untitled edit tab from File → New File, the empty-state screen, or the Open panel accessory. Closing the last tab leaves the empty placeholder (no auto-Untitled); cold launch still creates one Untitled when nothing was opened.
- Open / Save / Save As / Close Tab; dirty mark `•` in the tab title
- **Dirty close / quit:** Save / Don’t Save / Cancel sheets per modified tab (Untitled uses Save As); window shows the document-edited proxy; last window close quits
- Shared Forth console over `edit.sock` (thicker splitter; `consolePaneHeight`)
- Pending-goto and `debugLocation` find-or-open by path/inode; nested DEBUG steps open multiple files and restore the prior tab when stepping out
- Per-tab caret and top visible line on tab switch
- **Line numbers** (source editor only): SZ / FILE-ECHO style 5-column right-justified gutter
- **Find:** Edit → Find… / Find Next / Find Previous (`⌘F` / `⌘G` / `⌘⇧G`) on the TextEdit-style find bar
- **⌘-click VIEW:** sends sock `viewWord`; on miss or when Forth is disconnected, searches the open file and opens the find bar (`Hyper: not connected` note ends with a CR)
- Home / End → start/end of line; ⌘-Home / ⌘-End → start/end of file (Shift extends selection)
- **Debug toolbar** while 64Forth ITC DEBUG/TDBG is armed: Step Over / Into / Out / Continue / Stop
  - While armed the Forth command field is **disabled** and focus moves to the editor
  - Shortcuts: **F6** over, **F7** into, **F8** out, **F5** / **⌘⇧Y** continue, **Esc** stop
  - In browse mode, Forth letter keys also work (`Space`/`o` over, `i` into, `g` continue, `q` stop)
- **View → Browse Mode** (⌘⇧B) toggles browse ↔ Allow Editing (system View menu)
- Ping reconnects the socket only (never evaluates Forth / WORDS)
- **DEBUG word highlight:** prefers dbg-map `off`/`len` from sock `debugLocation`; else whole-word name search near the VIEW line with runtime→source aliases. Pastel green wash; clears on next pause or session end.

Still ahead: splits, session restore, breakpoints, deeper XPC.

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
    SixtyFourEditApp.swift      App entry (single Window workspace)
    AppDelegate.swift           open -a / Finder opens; dirty quit sheets
    WorkspaceModel.swift        Tabs, New File, dirty Save sheets, pending-goto
    SixtyFourDocument.swift     UTType / FileDocument helpers
    ContentView.swift           Tabs + editor + shared console + DebugToolbar
    EditorTextView.swift        NSTextView; goto; view-mode; DEBUG keys; Home/End
    LineNumberRulerView.swift   5-column right-justified source gutter
    ConsoleTranscriptView.swift Console NSTextView + ⌘-click VIEW
    FindSupport.swift           TextEdit find bar + VIEW-miss search
    DebugKeyMonitor.swift       Window-level F5–F8 / letters when editor not focused
    PendingGoto.swift           pending-goto.json consume + scroll + highlight
    FileMenuFixup.swift
    ForthConnectionManager.swift
    IPCProtocol.swift
    Info.plist
    Assets.xcassets/
```

## Status

Usable companion for 64Forth **1.5.3** (version lockstep): tabs, New File, dirty save sheets, line numbers, find / ⌘-click VIEW, DEBUG multi-file follow with span wash, sock steppers, Browse Mode. Leave `xcuserdata` unstaged when committing. No release in this push — DMG comes later.
