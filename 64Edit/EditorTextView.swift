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
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
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
            // Keep gotoLine until scroll succeeds (text may still be empty / not laid out).
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
        } else if !context.coordinator.didFallbackGoto, tv.string.count > 0 {
            // Fallback when ContentView never got a fileURL: match window path to pending-goto.
            DispatchQueue.main.async {
                guard !context.coordinator.didFallbackGoto else { return }
                let path = scroll.window?.representedURL?.path
                guard let pending = PendingGoto.consumeIfMatches(documentPath: path) else { return }
                context.coordinator.didFallbackGoto = true
                context.coordinator.parent.isViewMode = pending.viewMode
                if pending.line > 0 {
                    self.finishGoto(scroll: scroll, coordinator: context.coordinator, line: pending.line)
                }
            }
        }
    }

    private func finishGoto(scroll: NSScrollView, coordinator: Coordinator, line: Int) {
        guard coordinator.parent.gotoLine == nil || coordinator.parent.gotoLine == line else { return }
        guard let tv = scroll.documentView as? NSTextView else { return }
        if PendingGoto.scroll(tv, toLine: line) {
            coordinator.parent.gotoLine = nil
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        weak var textView: NSTextView?
        var didFallbackGoto = false
        private var keyMonitor: Any?
        private var isPrompting = false

        init(_ parent: EditorTextView) { self.parent = parent }

        deinit {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
        }

        func installKeyMonitor() {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handleKeyDown(event)
            }
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
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    self.parent.isViewMode = false
                    self.textView?.isEditable = true
                }
            }
        }
    }
}
