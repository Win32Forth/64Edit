# 64Edit

**Public domain.**

**64Edit** is the external source editor for **[64Forth](https://github.com/Win32Forth/64Forth)**. As of 64Forth **1.5.2**, the in-app SZ-EDITOR (`Library/Editor`) is removed. Edit Forth sources in 64Edit; 64Forth keeps the Console and App Output windows.

**Version lockstep:** 64Edit’s marketing version and build must match 64Forth. Current: **1.5.4** / build **48**.

Shipped beside **64Forth** in the dual-app DMG (from **1.5.2**). Drag **both** apps into `/Applications` (or keep them in the same folder). Gatekeeper Open Anyway applies once per app.

## How it connects

No special pairing after install. Both apps use the same Application Support paths:

1. Launch **64Forth** (it listens on a Unix domain socket).
2. Launch **64Edit**, or let 64Forth open it via `EDIT` / `VIEW` / DEBUG pause.
3. 64Edit connects to:

```text
~/Library/Application Support/64Forth/edit.sock
```

If 64Forth is not running, **Ping** launches the **flavor-matched** `64Forth.app` and retries `edit.sock` (silent when already connected — no pong line). You can also start 64Forth yourself and Ping to reconnect.

**Companion launch (flavor match):** Debug builds open the Debug companion (sibling Products folder, then newest DerivedData Debug). Release builds open sibling or `/Applications` only — never a Debug DerivedData build. The same rule applies in both directions (`64Edit` ↔ `64Forth`). When 64Edit is already connected on `edit.sock`, 64Forth skips `/usr/bin/open -a` so the window does not flash/reactivate. Socket IPC works regardless of where the apps live.

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
- Shared Forth console over `edit.sock` (splitter; live height in memory, `consolePaneHeight` saved on drag end; global-coordinate drag so the pane does not oscillate)
- Pending-goto and `debugLocation` find-or-open by path/inode; nested DEBUG steps open multiple files and restore the prior tab when stepping out
- Per-tab caret and top visible line on tab switch
- **Line numbers** (source editor only): SZ / FILE-ECHO style 5-column right-justified gutter; **View → Show Line Numbers** toggles the ruler (`showLineNumbers`, default on)
- **Find / Replace:** Edit → Find… / Find and Replace… / Find Next / Find Previous (`⌘F` / `⌥⌘F` / `⌘G` / `⌘⇧G`), plus Replace / Replace and Find Next / Replace All on the TextEdit-style find bar (no-op while a tab is in browse/view mode)
- **⌘-click VIEW:** sends sock `viewWord`; on miss or when Forth is disconnected, searches the open file and opens the find bar (`Hyper: not connected` note ends with a CR). Disconnected ⌘-click does **not** unhide a hidden Forth console.
- Home / End → start/end of line; ⌘-Home / ⌘-End → start/end of file (Shift extends selection)
- **Debug toolbar** while 64Forth ITC DEBUG/TDBG is armed: Breakpoints / Arm / Step Over / Into / Out / Continue / Stop
  - While armed the Forth command field is **disabled** and focus moves to the editor
  - Shortcuts: **F6** over, **F7** into, **F8** out, **F5** / **⌘⇧Y** continue, **Esc** stop
  - In browse mode, Forth letter keys also work (`Space`/`o` over, `i` into, `g` continue, `q` stop)
  - **Arm** continues until an enabled BREAK hits (sets host `debug_bp_go` then Continue)
- **View menu** (system View via `CommandGroup(after: .toolbar)`):
  - **Browse Mode** (⌘⇧B) toggles browse ↔ Allow Editing
  - **Show Forth Console** (`showForthChrome`, default on): hides status/Ping/Breakpoints, transcript, command line, splitter, and Debug toolbar for stand-alone editing. Sock still starts. Auto-reveals (and stays shown) on DEBUG arm, console traffic, or `lastError` only when already connected — not on cold Engine-down alone, and not on disconnected ⌘-click.
  - **Show Line Numbers**
- **Ping:** reconnect only (never evaluates Forth / WORDS). If `edit.sock` is down, launches flavor-matched 64Forth and retries connect. No `pong` console echo.
- **Breakpoints** button (console header next to Ping, and on the Debug toolbar): popover lists slots with enable checkbox and delete; Arm is active while paused
- **DEBUG word highlight:** prefers dbg-map `off`/`len` from sock `debugLocation`; else whole-word name search near the VIEW line with runtime→source aliases. Pastel green wash; clears on next pause or session end.
- **BREAK Pass 1–2:** **F9** / **⌘\\** / Debug → Toggle Breakpoint marks the Forth token under the caret via sock `toggleBreakpoint` → host `TOGGLE-BREAK` (8 xt slots). Sock `breakpoints(entries:)` syncs name+enabled. Wash: enabled pale-red, disabled gray. Idle arming still uses console **`BPGO <word>`**. Toggle is idle-only while DEBUG is paused. ⌘\\ is no longer Wrap Lines (hard wrap stays off).

Still ahead (optional): splits, session restore, BREAK gutter marks, idle Arm word picker, toggle-while-paused, deeper XPC.

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

Usable companion for 64Forth **1.5.4** (version lockstep **1.5.4** / build **48**): tabs, New File, dirty save sheets, line numbers, find / ⌘-click VIEW, DEBUG multi-file follow with span wash, sock steppers, Browse Mode, Pass 1–2 BREAK (F9/⌘\\, Breakpoints panel, Arm, pale-red/gray wash), View → Show Forth Console / Show Line Numbers, Ping launches flavor-matched 64Forth, smooth console splitter (persist on drag end + global drag coordinates; opaque transcript). Shipped in the dual-app DMG with 64Forth **v1.5.4**; standalone `Releases/64Edit-1.5.4-macOS.dmg` also available. Leave `xcuserdata` unstaged when committing.
