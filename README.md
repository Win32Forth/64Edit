# 64Edit

**Public domain.**

**64Edit** is the external source editor for **[64Forth](https://github.com/Win32Forth/64Forth)**. As of 64Forth **1.5.2**, the in-app SZ-EDITOR (`Library/Editor`) is removed. Edit Forth sources in 64Edit; 64Forth keeps the Console and App Output windows.

## How it connects

1. Launch **64Forth** (it listens on a Unix domain socket).
2. Launch **64Edit**, or let 64Forth open it via `EDIT` / `VIEW`.
3. 64Edit connects to:

```text
~/Library/Application Support/64Forth/edit.sock
```

If 64Forth is not running, 64Edit reports that the socket is missing. Start 64Forth, then reconnect (or relaunch 64Edit).

Shared IPC types live in `64Edit/IPCProtocol.swift` (mirrored on the 64Forth side as `App/IPCProtocol.swift`).

## EDIT and VIEW from 64Forth

64Forth opens files with `/usr/bin/open -a` against a Debug DerivedData `64Edit.app` when present, else `/Applications/64Edit.app`. Line targeting uses a small side channel (not XPC yet):

```text
~/Library/Application Support/64Forth/pending-goto.json
```

plus a wake-up DistributedNotification `com.Win32Forth.64Edit.goto`. Always consume the JSON file; notification `userInfo` is not reliable across processes.

| From 64Forth | pending-goto | 64Edit behavior |
|--------------|--------------|-----------------|
| `EDIT` path  | `mode: "edit"`, optional no line | Opens editable |
| `VIEW` / `EDIT-AT` path:line | `mode: "view"`, `line` | Scrolls to the line; **View mode** (read-only) |

**View mode:** yellow banner, `NSTextView` not editable. Typing (or cut/paste/undo) asks **Switch to Edit mode?** Yes/No. Banner **Edit** or ⌘⇧E also unlocks editing. Path matching uses standardized paths, then same-inode / `fileResourceIdentifier` so hard-linked Library copies still jump correctly.

The bottom Forth console pane is user-resizable (drag the splitter); height is stored in AppStorage `consolePaneHeight`.

Deeper XPC and debugger-highlight integration remain on the future agenda. Multi-file workspace (tabs/splits + one shared REPL) is planned; today’s DocumentGroup + per-window console is interim.

## Build

Open `64Edit.xcodeproj` in Xcode and run the **64Edit** scheme (Debug or Release) on macOS.

With Command Line Tools as the default `xcode-select`, set:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

before `xcodebuild` (or use full Xcode).

Requires a recent Xcode / macOS SwiftUI document-based app support.

## Layout

```text
64Edit/
  64Edit.xcodeproj/
  64Edit/
    SixtyFourEditApp.swift   App entry (DocumentGroup)
    SixtyFourDocument.swift  Document model
    ContentView.swift        Editor + resizable console + view-mode banner
    EditorTextView.swift     NSTextView; goto scroll; view-mode guard
    PendingGoto.swift        pending-goto.json consume + scroll
    FileMenuFixup.swift
    ForthConnectionManager.swift
    IPCProtocol.swift
    Info.plist
    Assets.xcassets/
```

## Status

Document UI, font size / wrap, resizable Forth console over `edit.sock`, and VIEW/EDIT open with line scroll and view mode. Deeper XPC and debugger highlight integration are still ahead.
