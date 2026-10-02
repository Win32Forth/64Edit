//
//  ContentView.swift
//  64Edit
//
//  Created by Tom Zimmer on 9/29/26.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @Binding var document: ForthDocument
    var fileURL: URL?
    @AppStorage("editorFontSize") private var fontSize = 13.0
    @AppStorage("editorWrap") private var wrapLines = false
    /// Height of the Forth console pane; drag the splitter to change it.
    @AppStorage("consolePaneHeight") private var consoleHeight = 160.0
    @EnvironmentObject private var forth: ForthConnectionManager
    @State private var commandLine = ""
    @State private var gotoLine: Int?
    @State private var isViewMode = false
    @State private var gotoObserver: NSObjectProtocol?
    @State private var gotoApplied = false
    @State private var dragStartHeight: CGFloat?

    private static let consoleMinHeight: CGFloat = 88
    private static let editorMinHeight: CGFloat = 120

    var body: some View {
        GeometryReader { geo in
            let maxConsole = max(
                Self.consoleMinHeight,
                geo.size.height - Self.editorMinHeight - ConsoleSplitter.height
            )
            let clampedConsole = min(max(consoleHeight, Self.consoleMinHeight), maxConsole)

            VStack(spacing: 0) {
                if isViewMode {
                    HStack(spacing: 8) {
                        Text("View mode")
                            .fontWeight(.semibold)
                        Text("Read-only — typing asks to switch to Edit")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Edit") {
                            isViewMode = false
                        }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(Color.yellow.opacity(0.22))
                }

                EditorTextView(
                    text: $document.text,
                    fontSize: fontSize,
                    wrap: wrapLines,
                    gotoLine: $gotoLine,
                    isViewMode: $isViewMode
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if forth.isDebugSessionArmed {
                    DebugToolbar(forth: forth)
                }

                ConsoleSplitter(
                    onDrag: { translationY in
                        let base = dragStartHeight ?? clampedConsole
                        if dragStartHeight == nil { dragStartHeight = clampedConsole }
                        let next = min(
                            max(base - translationY, Self.consoleMinHeight),
                            maxConsole
                        )
                        consoleHeight = next
                    },
                    onEnd: { dragStartHeight = nil }
                )

                consolePane
                    .frame(height: clampedConsole)
            }
            .onChange(of: geo.size.height) { _, _ in
                // Keep stored height inside the new window bounds.
                if consoleHeight > maxConsole {
                    consoleHeight = maxConsole
                }
            }
        }
        .background(WindowPathReader { window in
            // DocumentGroup often leaves fileURL nil; representedURL arrives with the window.
            if !gotoApplied {
                applyPendingGoto(window: window)
            }
        })
        .onAppear {
            installGotoObserver()
            scheduleApplyPendingGoto()
        }
        .onDisappear {
            if let gotoObserver {
                DistributedNotificationCenter.default().removeObserver(gotoObserver)
                self.gotoObserver = nil
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            scheduleApplyPendingGoto()
        }
        .onChange(of: document.text) { _, newText in
            // DocumentGroup often delivers fileURL/text after first appear.
            if !newText.isEmpty {
                scheduleApplyPendingGoto()
            }
        }
        .onChange(of: forth.debugLocation) { _, loc in
            guard let loc else { return }
            applyDebugLocation(loc)
        }
    }

    private var consolePane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(forth.isConnected ? "Engine connected" : "Engine down")
                if forth.isDebugSessionArmed {
                    Text("· debugging")
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Ping") {
                    forth.ping()
                }
            }
            if let err = forth.lastError {
                Text(err)
                    .foregroundStyle(.red)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(forth.consoleLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                }
                .onChange(of: forth.consoleLines.count) { _, _ in
                    if let last = forth.consoleLines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            HStack {
                TextField("Forth command", text: $commandLine)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(sendCommand)
                Button("Send", action: sendCommand)
                    .disabled(commandLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func sendCommand() {
        let cmd = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        forth.send(.executeCommand(command: cmd))
        commandLine = ""
    }

    /// Retry a few times: fileURL and document text can lag DocumentGroup open.
    private func scheduleApplyPendingGoto() {
        applyPendingGoto(window: nil)
        for delay in [0.05, 0.15, 0.4, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                applyPendingGoto(window: nil)
            }
        }
    }

    private func applyPendingGoto(window: NSWindow?) {
        guard !gotoApplied else { return }
        let candidates = PendingGoto.candidatePaths(explicit: fileURL, window: window)
        guard !candidates.isEmpty else { return }
        if let pending = PendingGoto.consumeIfMatches(candidates: candidates) {
            gotoApplied = true
            isViewMode = pending.viewMode
            if pending.line > 0 {
                gotoLine = pending.line
            }
        }
    }

    /// Sock `debugLocation`: scroll this window when it already shows the paused file.
    private func applyDebugLocation(_ loc: ForthConnectionManager.DebugLocation) {
        let candidates = PendingGoto.candidatePaths(explicit: fileURL, window: nil)
        guard candidates.contains(where: { PendingGoto.pathsMatch($0, loc.path) }) else {
            return
        }
        isViewMode = true
        if loc.line > 0 {
            gotoLine = loc.line
        }
    }

    private func installGotoObserver() {
        guard gotoObserver == nil else { return }
        gotoObserver = DistributedNotificationCenter.default().addObserver(
            forName: PendingGoto.notificationName,
            object: nil,
            queue: .main
        ) { _ in
            // userInfo is not delivered across processes; always use the pending file.
            gotoApplied = false
            scheduleApplyPendingGoto()
        }
    }
}

/// Shown while 64Forth ITC DEBUG / TDBG is armed; hidden otherwise.
private struct DebugToolbar: View {
    @ObservedObject var forth: ForthConnectionManager

    /// Pale green when sock is up; pale orange when armed but disconnected.
    private var barColor: Color {
        forth.isConnected
            ? Color.green.opacity(0.18)
            : Color.orange.opacity(0.18)
    }

    private var accent: Color {
        forth.isConnected ? .green : .orange
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "ladybug.fill")
                .foregroundStyle(accent)
            Text("Debug")
                .fontWeight(.semibold)
            Spacer(minLength: 8)
            // No bare letter shortcuts — they would steal typing from the editor
            // and command field. F6/F7/g/q still work in the 64Forth console.
            Button("Step Over") { forth.stepOver() }
            Button("Step Into") { forth.stepInto() }
            Button("Continue") { forth.resumeDebug() }
            Button("Stop") { forth.stopDebug() }
                .foregroundStyle(.red)
        }
        .font(.system(size: 11))
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(barColor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Debug toolbar")
    }
}

/// Drag handle between editor and console; drag up to grow the console.
private struct ConsoleSplitter: View {
    static let height: CGFloat = 6

    var onDrag: (CGFloat) -> Void
    var onEnd: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
            Rectangle()
                .fill(Color.clear)
                .frame(height: Self.height)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            onDrag(value.translation.height)
                        }
                        .onEnded { _ in
                            onEnd()
                        }
                )
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Resize console")
        .accessibilityAddTraits(.isButton)
    }
}

/// Reads the hosting NSWindow so we can use representedURL when fileURL is nil.
private struct WindowPathReader: NSViewRepresentable {
    var onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { publish(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { publish(from: nsView) }
    }

    private func publish(from view: NSView) {
        guard let window = view.window else { return }
        onResolve(window)
    }
}

#Preview {
    ContentView(document: .constant(ForthDocument()), fileURL: nil)
        .environmentObject(ForthConnectionManager())
}
