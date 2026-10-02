//
//  PendingGoto.swift
//  64Edit
//
//  64Forth writes pending-goto.json (and a distributed notification) before
//  opening a file via VIEW / EDIT / EDIT-AT. Consume it to scroll and set mode.
//

import Foundation
import AppKit

enum PendingGoto {
    static let notificationName = Notification.Name("com.Win32Forth.64Edit.goto")

    struct Request: Equatable {
        var path: String
        /// 1-based line to reveal; 0 means open only (no scroll).
        var line: Int
        /// VIEW → true (read-only until user switches); EDIT → false.
        var viewMode: Bool
    }

    static var fileURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root
            .appendingPathComponent("64Forth", isDirectory: true)
            .appendingPathComponent("pending-goto.json")
    }

    /// JSONSerialization boxes numbers as NSNumber; `as? Int` can fail.
    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        return nil
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        if let i = any as? Int { return Double(i) }
        return nil
    }

    /// Peek without removing. Returns nil if missing, stale (>60s), or invalid.
    static func peek() -> Request? {
        let url = fileURL
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = obj["path"] as? String,
              !path.isEmpty
        else { return nil }
        let line = intValue(obj["line"]) ?? 0
        let mode = (obj["mode"] as? String)?.lowercased()
        // Legacy pending files had no mode: line > 0 meant VIEW.
        let viewMode: Bool
        if mode == "view" {
            viewMode = true
        } else if mode == "edit" {
            viewMode = false
        } else {
            guard line > 0 else { return nil }
            viewMode = true
        }
        let created = doubleValue(obj["created"]) ?? 0
        if created > 0, Date().timeIntervalSince1970 - created > 60 {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return Request(path: path, line: line, viewMode: viewMode)
    }

    static func consume() -> Request? {
        guard let pending = peek() else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        return pending
    }

    /// Consume only when `documentPath` matches the pending path (string or same inode).
    static func consumeIfMatches(documentPath: String?) -> Request? {
        guard let documentPath,
              let pending = peek(),
              pathsMatch(documentPath, pending.path)
        else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        return pending
    }

    /// Consume when any candidate path matches the pending file.
    static func consumeIfMatches(candidates: [String]) -> Request? {
        guard let pending = peek(), !candidates.isEmpty else { return nil }
        guard candidates.contains(where: { pathsMatch($0, pending.path) }) else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        return pending
    }

    /// Paths for this document window only (never other open docs — avoids wrong-window goto).
    static func candidatePaths(explicit: URL?, window: NSWindow? = nil) -> [String] {
        var out: [String] = []
        func add(_ s: String?) {
            guard let s, !s.isEmpty else { return }
            if !out.contains(where: { pathsMatch($0, s) }) { out.append(s) }
        }
        add(explicit?.path)
        add(window?.representedURL?.path)
        // When DocumentGroup has not yet passed fileURL, the key window may already know it.
        if explicit == nil, let key = NSApp.keyWindow {
            add(key.representedURL?.path)
        }
        return out
    }

    static func pathsMatch(_ a: String, _ b: String) -> Bool {
        let ua = URL(fileURLWithPath: a).standardizedFileURL
        let ub = URL(fileURLWithPath: b).standardizedFileURL
        if ua.path.caseInsensitiveCompare(ub.path) == .orderedSame {
            return true
        }
        // Library copies are often hard-linked; DocumentGroup may report the other path.
        guard let aId = try? ua.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
              let bId = try? ub.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        else {
            return false
        }
        return aId.isEqual(bId)
    }

    /// Select and scroll `tv` so 1-based `line` is visible. Returns false if text is empty.
    @discardableResult
    static func scroll(_ tv: NSTextView, toLine line: Int) -> Bool {
        guard line > 0 else { return false }
        let ns = tv.string as NSString
        guard ns.length > 0 else { return false }
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
        if let layout = tv.layoutManager, let container = tv.textContainer {
            layout.ensureLayout(for: container)
            let glyph = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyph, in: container)
            let visible = rect.insetBy(dx: 0, dy: -tv.bounds.height / 3)
            tv.scrollToVisible(visible)
        }
        tv.window?.makeFirstResponder(tv)
        return true
    }
}
