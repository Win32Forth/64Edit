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
        return scroll
    }
    
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        tv.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        
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
    }
    
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        weak var textView: NSTextView?
        init(_ parent: EditorTextView) { self.parent = parent }
        
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
