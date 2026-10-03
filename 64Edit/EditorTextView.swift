//
//  EditorTextView.swift
//  64Edit
//
//  Created by Tom's MacBook Air on 9/29/26.
//

import SwiftUI
import AppKit

struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var wrap: Bool
    /// 1-based line to reveal once; ContentView clears after apply.
    @Binding var gotoLine: Int?
    /// VIEW opens read-only; typing prompts to switch into edit mode.
    @Binding var isViewMode: Bool
    /// Per-tab caret / selection (saved while editing, restored on tab switch).
    @Binding var selection: NSRange
    /// Per-tab 1-based top visible line.
    @Binding var topVisibleLine: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let tv = NSTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isEditable = !isViewMode
        tv.isSelectable = true
        tv.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        tv.string = text
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = !wrap
        tv.textContainer?.containerSize = NSSize(
            width: wrap ? 100 : CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        tv.textContainer?.widthTracksTextView = wrap
        tv.autoresizingMask = wrap ? [.width] : []

        scroll.documentView = tv
        context.coordinator.textView = tv
        context.coordinator.installKeyMonitor()
        context.coordinator.installScrollObserver(on: scroll)
        context.coordinator.needsRestore = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }

        let textChanged = tv.string != text
        if textChanged {
            // Replacing the string resets caret/scroll; restore afterward unless goto wins.
            context.coordinator.suppressSave = true
            tv.string = text
            context.coordinator.suppressSave = false
            context.coordinator.needsRestore = true
        }
        tv.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        tv.isEditable = !isViewMode

        tv.isHorizontallyResizable = !wrap
        tv.autoresizingMask = wrap ? [.width] : []
        tv.textContainer?.widthTracksTextView = wrap
        if wrap {
            tv.textContainer?.containerSize = NSSize(
                width: scroll.contentSize.width,
                height: CGFloat.greatestFiniteMagnitude
            )
        } else {
            tv.textContainer?.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }

        if let line = gotoLine, line > 0 {
            context.coordinator.needsRestore = false
            let attempt = line
            DispatchQueue.main.async {
                self.finishGoto(scroll: scroll, coordinator: context.coordinator, line: attempt)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.finishGoto(scroll: scroll, coordinator: context.coordinator, line: attempt)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.finishGoto(scroll: scroll, coordinator: context.coordinator, line: attempt)
            }
        } else if context.coordinator.needsRestore {
            let attemptSelection = selection
            let attemptTop = topVisibleLine
            DispatchQueue.main.async {
                context.coordinator.restoreViewState(
                    scroll: scroll,
                    selection: attemptSelection,
                    topLine: attemptTop
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                context.coordinator.restoreViewState(
                    scroll: scroll,
                    selection: attemptSelection,
                    topLine: attemptTop
                )
            }
        }
    }

    private func finishGoto(scroll: NSScrollView, coordinator: Coordinator, line: Int) {
        guard coordinator.parent.gotoLine == nil || coordinator.parent.gotoLine == line else { return }
        guard let tv = scroll.documentView as? NSTextView else { return }
        coordinator.suppressSave = true
        if PendingGoto.scroll(tv, toLine: line) {
            coordinator.parent.gotoLine = nil
            coordinator.captureViewState(from: tv)
            coordinator.needsRestore = false
        }
        coordinator.suppressSave = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        weak var textView: NSTextView?
        private var keyMonitor: Any?
        private var scrollObserver: NSObjectProtocol?
        private var isPrompting = false
        /// Skip writing bindings while we programmatically move caret/scroll.
        var suppressSave = false
        /// Apply saved selection / top line once the view is ready.
        var needsRestore = false

        init(_ parent: EditorTextView) { self.parent = parent }

        deinit {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
        }

        func installKeyMonitor() {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handleKeyDown(event)
            }
        }

        func installScrollObserver(on scroll: NSScrollView) {
            guard scrollObserver == nil else { return }
            scroll.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView,
                queue: .main
            ) { [weak self] _ in
                guard let self, let tv = self.textView, !self.suppressSave else { return }
                self.captureViewState(from: tv)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !suppressSave,
                  let tv = notification.object as? NSTextView
            else { return }
            captureViewState(from: tv)
        }

        func captureViewState(from tv: NSTextView) {
            let sel = tv.selectedRange()
            let clamped = Self.clampedSelection(sel, in: tv.string)
            if parent.selection != clamped {
                parent.selection = clamped
            }
            let top = Self.topVisibleLine(of: tv)
            if parent.topVisibleLine != top {
                parent.topVisibleLine = top
            }
        }

        func restoreViewState(scroll: NSScrollView, selection: NSRange, topLine: Int) {
            guard needsRestore else { return }
            guard parent.gotoLine == nil else { return }
            guard let tv = scroll.documentView as? NSTextView else { return }
            suppressSave = true
            let sel = Self.clampedSelection(selection, in: tv.string)
            tv.setSelectedRange(sel)
            _ = Self.scroll(tv, soTopLineIs: topLine)
            // Layout may still be settling; only clear after a successful pin, or accept
            // line 1 / empty as done so we do not loop forever.
            if tv.string.isEmpty || topLine <= 1 || Self.topVisibleLine(of: tv) > 0 {
                needsRestore = false
                parent.selection = sel
                parent.topVisibleLine = max(1, Self.topVisibleLine(of: tv))
            }
            suppressSave = false
        }

        static func clampedSelection(_ range: NSRange, in string: String) -> NSRange {
            let len = (string as NSString).length
            let loc = min(max(0, range.location), len)
            let maxLen = len - loc
            let length = min(max(0, range.length), maxLen)
            return NSRange(location: loc, length: length)
        }

        /// 1-based line at the top of the visible clip.
        static func topVisibleLine(of tv: NSTextView) -> Int {
            guard let scroll = tv.enclosingScrollView,
                  let layout = tv.layoutManager,
                  let container = tv.textContainer
            else { return 1 }
            layout.ensureLayout(for: container)
            guard layout.numberOfGlyphs > 0 else { return 1 }
            let origin = scroll.contentView.bounds.origin
            var point = tv.convert(origin, from: scroll.contentView)
            point.x -= tv.textContainerOrigin.x
            point.y -= tv.textContainerOrigin.y
            point.y = max(0, point.y)
            let glyphIndex = layout.glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: nil)
            let safeGlyph = min(max(0, glyphIndex), layout.numberOfGlyphs - 1)
            let charIndex = layout.characterIndexForGlyph(at: safeGlyph)
            return lineNumber(forCharacter: charIndex, in: tv.string)
        }

        /// Pin `line` (1-based) to the top of the scroll view. Returns false if empty.
        @discardableResult
        static func scroll(_ tv: NSTextView, soTopLineIs line: Int) -> Bool {
            let ns = tv.string as NSString
            guard ns.length > 0 else { return false }
            let target = max(1, line)
            var current = 1
            var idx = 0
            while current < target && idx < ns.length {
                let para = ns.paragraphRange(for: NSRange(location: idx, length: 0))
                let next = NSMaxRange(para)
                if next <= idx { break }
                idx = next
                current += 1
            }
            let loc = min(idx, max(0, ns.length - 1))
            let range = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            guard let layout = tv.layoutManager,
                  let container = tv.textContainer,
                  let scroll = tv.enclosingScrollView
            else {
                tv.scrollRangeToVisible(range)
                return true
            }
            layout.ensureLayout(for: container)
            let glyph = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyph, in: container)
            let pointInTV = NSPoint(
                x: 0,
                y: rect.origin.y + tv.textContainerOrigin.y
            )
            let pointInClip = scroll.contentView.convert(pointInTV, from: tv)
            let clip = scroll.contentView
            let maxY = max(0, (scroll.documentView?.bounds.height ?? 0) - clip.bounds.height)
            let y = min(max(0, pointInClip.y), maxY)
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
            scroll.reflectScrolledClipView(clip)
            return true
        }

        static func lineNumber(forCharacter index: Int, in string: String) -> Int {
            let ns = string as NSString
            guard ns.length > 0 else { return 1 }
            let loc = min(max(0, index), ns.length)
            var current = 1
            var idx = 0
            while idx < loc {
                let para = ns.paragraphRange(for: NSRange(location: idx, length: 0))
                let next = NSMaxRange(para)
                if next <= idx { break }
                if next > loc { break }
                idx = next
                current += 1
            }
            return current
        }

        private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            guard parent.isViewMode,
                  let tv = textView,
                  tv.window?.isKeyWindow == true,
                  tv.window?.firstResponder === tv || tv.window?.firstResponder === tv.enclosingScrollView
                    || (tv.window?.firstResponder as? NSView)?.isDescendant(of: tv) == true
            else {
                return event
            }
            // Allow navigation / copy / find; block edits.
            if event.modifierFlags.contains(.command) {
                let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
                if ["c", "a", "f", "g"].contains(chars) { return event }
                if chars == "x" || chars == "v" || chars == "z" {
                    promptSwitchToEdit()
                    return nil
                }
                return event
            }
            if event.modifierFlags.contains(.function) || event.modifierFlags.contains(.numericPad) {
                return event
            }
            switch event.keyCode {
            case 123, 124, 125, 126, // arrows
                 115, 119, 116, 121, // home/end/page
                 48,  // tab (leave for focus; treat as edit attempt)
                 53:  // escape
                if event.keyCode == 48 {
                    promptSwitchToEdit()
                    return nil
                }
                return event
            case 51, 117: // delete / forward delete
                promptSwitchToEdit()
                return nil
            default:
                break
            }
            if let chars = event.characters, chars.contains(where: { !$0.isNewline && !$0.isWhitespace || $0.isNewline || $0.isWhitespace }) {
                // Any character / return / space is an edit attempt in view mode.
                if !chars.isEmpty {
                    promptSwitchToEdit()
                    return nil
                }
            }
            return event
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard parent.isViewMode else { return true }
            promptSwitchToEdit()
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            if !suppressSave {
                captureViewState(from: tv)
            }
        }

        private func promptSwitchToEdit() {
            guard !isPrompting else { return }
            isPrompting = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                defer { self.isPrompting = false }
                guard self.parent.isViewMode else { return }
                let alert = NSAlert()
                alert.messageText = "Switch to Edit mode?"
                alert.informativeText = "This file was opened with VIEW and is read-only."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Yes")
                alert.addButton(withTitle: "No")
                // Esc dismisses like No (stay in view mode).
                alert.buttons.last?.keyEquivalent = "\u{1b}"
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    self.parent.isViewMode = false
                    self.textView?.isEditable = true
                }
            }
        }
    }
}
