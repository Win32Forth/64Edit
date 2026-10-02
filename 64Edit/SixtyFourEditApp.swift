//
//  SixtyFourEditApp.swift
//  64Edit
//
//  Created by Tom Zimmer on 9/29/26.
//

import SwiftUI

@main
struct SixtyFourEditApp: App {
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
        DocumentGroup(newDocument: ForthDocument()) { file in
            ContentView(document: file.$document)
                .environmentObject(forth)
                .onAppear { forth.start() }
        }
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Save As…") {
                    NSApp.sendAction(
                        #selector(NSDocument.saveAs(_:)),
                        to: nil,
                        from: nil
                    )
                }
            }
            CommandGroup(after: .textFormatting) {
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
