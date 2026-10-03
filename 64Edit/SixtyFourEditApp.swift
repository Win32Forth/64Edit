//
//  SixtyFourEditApp.swift
//  64Edit
//
//  Created by Tom Zimmer on 9/29/26.
//

import SwiftUI

@main
struct SixtyFourEditApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workspace = WorkspaceModel()
    @StateObject private var forth = ForthConnectionManager()

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            FileMenuFixup.install()
        }
    }

    var body: some Scene {
        // Single workspace window (not DocumentGroup / multi-window).
        Window("64Edit", id: "workspace") {
            ContentView()
                .environmentObject(workspace)
                .environmentObject(forth)
                .frame(minWidth: 640, minHeight: 420)
                .onAppear {
                    appDelegate.attach(workspace: workspace)
                    forth.start()
                }
        }
        .defaultSize(width: 960, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New File") {
                    workspace.newFile()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open…") {
                    workspace.openPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    _ = workspace.saveSelected()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As…") {
                    _ = workspace.saveSelectedAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Close Tab") {
                    // Last tab → empty placeholder (New File / Open…), not auto-Untitled.
                    workspace.closeSelected()
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            // TextEdit-style find bar on the focused editor / console NSTextView.
            // (SwiftUI Edit→Find alone often misses embedded AppKit text views.)
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find…") {
                    FindSupport.perform(.showFindInterface)
                }
                .keyboardShortcut("f", modifiers: .command)
                Button("Find Next") {
                    FindSupport.perform(.nextMatch)
                }
                .keyboardShortcut("g", modifiers: .command)
                Button("Find Previous") {
                    FindSupport.perform(.previousMatch)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Use Selection for Find") {
                    FindSupport.perform(.setSearchString)
                }
                // No ⌘E — that stays free for future VIEW-under-caret; use the menu.
            }
            // Merge into the system View menu (CommandMenu("View") creates a second one).
            CommandGroup(after: .toolbar) {
                Button(workspace.selectedTab?.isViewMode == true ? "Allow Editing" : "Browse Mode") {
                    workspace.toggleBrowseMode()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(workspace.selectedTab == nil)
            }
            CommandMenu("Format") {
                Button("Bigger") {
                    bumpFont(1)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Smaller") {
                    bumpFont(-1)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Size (13)") {
                    UserDefaults.standard.set(13.0, forKey: "editorFontSize")
                }

                Toggle("Wrap Lines", isOn: Binding(
                    get: { UserDefaults.standard.object(forKey: "editorWrap") as? Bool ?? true },
                    set: { UserDefaults.standard.set($0, forKey: "editorWrap") }
                ))
                .keyboardShortcut("\\", modifiers: [.command])
            }
        }
    }

    private func bumpFont(_ delta: Double) {
        let key = "editorFontSize"
        let current = UserDefaults.standard.object(forKey: key) as? Double ?? 13
        let next = min(32, max(9, current + delta))
        UserDefaults.standard.set(next, forKey: key)
    }
}
