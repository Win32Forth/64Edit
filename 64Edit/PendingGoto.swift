//
//  PendingGoto.swift
//  64Edit
//
//  64Forth writes pending-goto.json (and a distributed notification) before
//  opening a file via VIEW / EDIT-AT. Consume it to scroll to the line.
//

import Foundation
import AppKit

enum PendingGoto {
    static let notificationName = Notification.Name("com.Win32Forth.64Edit.goto")

    static var fileURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root
            .appendingPathComponent("64Forth", isDirectory: true)
            .appendingPathComponent("pending-goto.json")
    }

    /// Peek without removing. Returns nil if missing, stale (>60s), or invalid.
    static func peek() -> (path: String, line: Int)? {
        let url = fileURL
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = obj["path"] as? String,
              let line = obj["line"] as? Int,
              line > 0
        else { return nil }
        let created = (obj["created"] as? Double) ?? 0
        if created > 0, Date().timeIntervalSince1970 - created > 60 {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return (path, line)
    }

    static func consume() -> (path: String, line: Int)? {
        guard let pending = peek() else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        return pending
    }

    /// Consume only when `documentPath` matches the pending path.
    static func consumeIfMatches(documentPath: String?) -> Int? {
        guard let documentPath,
              let pending = peek(),
              pathsMatch(documentPath, pending.path)
        else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        return pending.line
    }

    static func pathsMatch(_ a: String, _ b: String) -> Bool {
        let sa = URL(fileURLWithPath: a).standardizedFileURL.path
        let sb = URL(fileURLWithPath: b).standardizedFileURL.path
        return sa.caseInsensitiveCompare(sb) == .orderedSame
    }

    /// Select and scroll `tv` so 1-based `line` is visible.
    static func scroll(_ tv: NSTextView, toLine line: Int) {
        guard line > 0 else { return }
        let ns = tv.string as NSString
        guard ns.length > 0 else { return }
        var current = 1
        var idx = 0
        while current < line && idx < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: idx, length: 0))
            let next = NSMaxRange(para)
            if next <= idx { break }
            idx = next
            current += 1
        }
        let loc = min(idx, max(0, ns.length - 1))
        let range = ns.paragraphRange(for: NSRange(location: loc, length: 0))
        tv.setSelectedRange(range)
        tv.scrollRangeToVisible(range)
        tv.window?.makeFirstResponder(tv)
    }
}
