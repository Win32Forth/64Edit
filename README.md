# 64Edit

**Public domain.**

**64Edit** is the external source editor for **[64Forth](https://github.com/Win32Forth/64Forth)**. As of 64Forth **1.5.2**, the in-app SZ-EDITOR (`Library/Editor`) is removed. Edit Forth sources in 64Edit; 64Forth keeps the Console and App Output windows.

Shipped beside **64Forth** in the **1.5.2** dual-app DMG. Drag **both** apps into `/Applications` (or keep them in the same folder). Marketing version **1.0** (first companion release).

## How it connects

No special pairing after install. Both apps use the same Application Support paths:

1. Launch **64Forth** (it listens on a Unix domain socket).
2. Launch **64Edit**, or let 64Forth open it via `EDIT` / `VIEW` / DEBUG pause.
3. 64Edit connects to:

```text
~/Library/Application Support/64Forth/edit.sock
```

If 64Forth is not running, 64Edit reports that the socket is missing. Start 64Forth, then use Ping (reconnect only) or relaunch 64Edit.

**Launch path:** 64Forth finds `64Edit.app` as a **sibling** of `64Forth.app`, or at `/Applications/64Edit.app`. Debug developer builds prefer Xcode DerivedData first. Socket IPC works regardless of where the apps live.

Shared IPC types live in `64Edit/IPCProtocol.swift` (mirrored on the 64Forth side as `App/IPCProtocol.swift`).

## EDIT, VIEW, and DEBUG from 64Forth

64Forth opens files with `/usr/bin/open -a` plus a small side channel (not XPC yet):

```text
~/Library/Application Support/64Forth/pending-goto.json
```

plus a wake-up DistributedNotification `com.Win32Forth.64Edit.goto`. Always consume the JSON file; notification `userInfo` is not reliable across processes. DEBUG pauses also send sock `debugLocation(path:line:)` so an already-running 64Edit can switch tabs without another launch when the path is unchanged.

| From 64Forth | pending-goto | 64Edit behavior |
|--------------|--------------|-----------------|
| `EDIT` path  | `mode: "edit"`, optional no line | Opens editable |
| `VIEW` / `EDIT-AT` / DEBUG pause | `mode: "view"`, `line` | Scrolls to the line; **View mode** (read-only) |

**View mode:** yellow banner, `NSTextView` not editable. Typing (or cut/paste/undo) asks **Switch to Edit mode?** Yes/No. Banner **Edit** or ⌘⇧E also unlocks editing. Each tab keeps its own view mode so debug-opened files stay browse until you unlock them. Path matching uses standardized paths, then same-inode / `fileResourceIdentifier`.

## Workspace (Slice 1)

Single `Window("64Edit")` with tabs (not DocumentGroup):

- Open / Save / Save As / Close Tab; dirty mark `•` in the tab title
- Shared Forth console over `edit.sock` (resizable splitter; `consolePaneHeight`)
- Pending-goto and `debugLocation` find-or-open by path/inode; nested DEBUG steps open multiple files and restore the prior tab when stepping out
- Per-tab caret and top visible line on tab switch
- **Debug toolbar** while 64Forth ITC DEBUG/TDBG is armed: Step Over / Into / Out / Continue / Stop (maps to console F6 / F7 / F8 / `g` / `q`)
- Ping reconnects the socket only (never evaluates Forth / WORDS)

Still ahead: dirty-close prompts, polished New/untitled, splits, session restore, breakpoints, deeper XPC highlight.

## Build

Open `64Edit.xcodeproj` in Xcode and run the **64Edit** scheme (Debug or Release) on macOS.

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
    EditorTextView.swift     NSTextView; goto scroll; view-mode guard
    PendingGoto.swift        pending-goto.json consume + scroll
    FileMenuFixup.swift
    ForthConnectionManager.swift
    IPCProtocol.swift
    Info.plist
    Assets.xcassets/
```

## Status

Usable companion for 64Forth **1.5.2**: tabs, view mode, DEBUG follow, sock steppers. Leave `xcuserdata` unstaged when committing.
