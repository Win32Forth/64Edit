//
//  ContentView.swift
//  64Edit
//
//  Created by Tom Zimmer on 9/29/26.
//

import SwiftUI
import AppKit

/// Single-window workspace: tab bar + editor + shared Forth console.
struct ContentView: View {
    @EnvironmentObject private var workspace: WorkspaceModel
    @EnvironmentObject private var forth: ForthConnectionManager
    @AppStorage("editorFontSize") private var fontSize = 13.0
    @AppStorage("editorWrap") private var wrapLines = false
    @AppStorage("consolePaneHeight") private var consoleHeight = 160.0
    @State private var commandLine = ""
    @State private var gotoObserver: NSObjectProtocol?
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
                tabBar

                if let tab = workspace.selectedTab {
                    TabEditorPane(tab: tab, fontSize: fontSize, wrapLines: wrapLines)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(tab.id)
                } else {
                    emptyEditorPlaceholder
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

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
                if consoleHeight > maxConsole {
                    consoleHeight = maxConsole
                }
            }
        }
        .background(WindowChrome(url: workspace.selectedTab?.fileURL))
        .onAppear {
            installGotoObserver()
            forth.start()
            // File opens / pending-goto / initial untitled are owned by AppDelegate.attach
            // (runs from SixtyFourEditApp) so we do not create a stray Untitled tab first.
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
            workspace.handlePendingGoto()
        }
        .onChange(of: forth.debugLocation) { _, loc in
            guard let loc else { return }
            workspace.applyDebugLocation(path: loc.path, line: loc.line)
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(workspace.tabs) { tab in
                    TabChip(
                        title: tab.title,
                        isSelected: tab.id == workspace.selectedTabID,
                        onSelect: { workspace.selectedTabID = tab.id },
                        onClose: { workspace.closeTab(id: tab.id) }
                    )
                }
            }
        }
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
    }

    private var emptyEditorPlaceholder: some View {
        VStack(spacing: 12) {
            Text("No file open")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Open a Forth source, or use EDIT / VIEW from 64Forth.")
                .foregroundStyle(.secondary)
            Button("Open…") { workspace.openPanel() }
                .keyboardShortcut("o", modifiers: .command)
        }
    }

    // MARK: - Console

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

    private func installGotoObserver() {
        guard gotoObserver == nil else { return }
        gotoObserver = DistributedNotificationCenter.default().addObserver(
            forName: PendingGoto.notificationName,
            object: nil,
            queue: .main
        ) { _ in
            workspace.handlePendingGoto()
        }
    }
}

// MARK: - Tab UI

private struct TabChip: View {
    var title: String
    var isSelected: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                Text(title)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close tab")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(height: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

/// Editor + view-mode banner for one tab (ObservedObject so text edits refresh dirty title).
private struct TabEditorPane: View {
    @ObservedObject var tab: EditorTab
    var fontSize: Double
    var wrapLines: Bool

    var body: some View {
        VStack(spacing: 0) {
            if tab.isViewMode {
                HStack(spacing: 8) {
                    Text("View mode")
                        .fontWeight(.semibold)
                    Text("Read-only — typing asks to switch to Edit")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit") {
                        tab.isViewMode = false
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
                text: Binding(
                    get: { tab.text },
                    set: { newValue in
                        if tab.text != newValue {
                            tab.text = newValue
                            tab.isDirty = true
                        }
                    }
                ),
                fontSize: fontSize,
                wrap: wrapLines,
                gotoLine: $tab.gotoLine,
                isViewMode: $tab.isViewMode,
                selection: Binding(
                    get: { tab.selection },
                    set: { tab.selection = $0 }
                ),
                topVisibleLine: Binding(
                    get: { tab.topVisibleLine },
                    set: { tab.topVisibleLine = $0 }
                )
            )
        }
    }
}

/// Shown while 64Forth ITC DEBUG / TDBG is armed; hidden otherwise.
private struct DebugToolbar: View {
    @ObservedObject var forth: ForthConnectionManager

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
            Button("Step Over") { forth.stepOver() }
            Button("Step Into") { forth.stepInto() }
            Button("Step Out") { forth.stepOut() }
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

/// Keep the window title / representedURL in sync with the selected tab.
private struct WindowChrome: NSViewRepresentable {
    var url: URL?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(from: nsView) }
    }

    private func apply(from view: NSView) {
        guard let window = view.window else { return }
        window.representedURL = url
        if let url {
            window.title = url.lastPathComponent
        } else if window.title.isEmpty {
            window.title = "64Edit"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkspaceModel())
        .environmentObject(ForthConnectionManager())
}
