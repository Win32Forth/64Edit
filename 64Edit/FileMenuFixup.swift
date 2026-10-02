//
//  FileMenuFixup.swift
//  64Edit
//
//  Created by Tom's MacBook Air on 9/29/26.
//

import AppKit

enum FileMenuFixup {
    static func install() {
        guard let file = NSApp.mainMenu?.item(withTitle: "File")?.submenu else { return }

        // ⌘⇧S must not stay on Duplicate
        if let dup = file.item(withTitle: "Duplicate") {
            dup.keyEquivalent = ""
            dup.keyEquivalentModifierMask = []
        }

        guard let saveAs = findSaveAs(in: file) else { return }

        saveAs.keyEquivalent = "s"
        saveAs.keyEquivalentModifierMask = [.command, .shift]

        // Place immediately above Duplicate
        file.removeItem(saveAs)
        if let dupIndex = file.items.firstIndex(where: { $0.title == "Duplicate" }) {
            file.insertItem(saveAs, at: dupIndex)
        } else {
            file.addItem(saveAs)
        }
    }

    private static func findSaveAs(in file: NSMenu) -> NSMenuItem? {
        file.items.first {
            $0.title == "Save As…" || $0.title == "Save As..."
        }
    }
}

