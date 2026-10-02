# 64Edit

**Public domain.**

**64Edit** is the external source editor for **[64Forth](https://github.com/Win32Forth/64Forth)**. As of 64Forth **1.5.2**, the in-app SZ-EDITOR (`Library/Editor`) is removed. Edit Forth sources in 64Edit; 64Forth keeps the Console and App Output windows.

## How it connects

1. Launch **64Forth** (it listens on a Unix domain socket).
2. Launch **64Edit**.
3. 64Edit connects to:

```text
~/Library/Application Support/64Forth/edit.sock
```

If 64Forth is not running, 64Edit reports that the socket is missing. Start 64Forth, then reconnect (or relaunch 64Edit).

Shared IPC types live in `64Edit/IPCProtocol.swift` (mirrored on the 64Forth side as `App/IPCProtocol.swift`).

## Build

Open `64Edit.xcodeproj` in Xcode and run the **64Edit** scheme (Debug or Release) on macOS.

Requires a recent Xcode / macOS SwiftUI document-based app support.

## Layout

```text
64Edit/
  64Edit.xcodeproj/
  64Edit/
    SixtyFourEditApp.swift   App entry (DocumentGroup)
    SixtyFourDocument.swift  Document model
    ContentView.swift
    EditorTextView.swift
    FileMenuFixup.swift
    ForthConnectionManager.swift
    IPCProtocol.swift
    Info.plist
    Assets.xcassets/
```

## Status

Early external-editor cut: document UI, font size / wrap, and a live socket client to 64Forth. Deeper XPC and debugger highlight integration are still ahead.
