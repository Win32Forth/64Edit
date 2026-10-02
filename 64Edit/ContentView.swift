//
//  ContentView.swift
//  64Edit
//
//  Created by Tom Zimmer on 9/29/26.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: ForthDocument
    var fileURL: URL?
    @AppStorage("editorFontSize") private var fontSize = 13.0
    @AppStorage("editorWrap") private var wrapLines = false
    @EnvironmentObject private var forth: ForthConnectionManager
    @State private var commandLine = ""
    @State private var gotoLine: Int?
    @State private var gotoObserver: NSObjectProtocol?

    var body: some View {
        VStack(spacing: 0) {
            EditorTextView(
                text: $document.text,
                fontSize: fontSize,
                wrap: wrapLines,
                gotoLine: $gotoLine
            )

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(forth.isConnected ? "Engine connected" : "Engine down")
                    Spacer()
                    Button("Ping") {
                        forth.send(.executeCommand(command: "WORDS"))
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
            .frame(minHeight: 120, maxHeight: 180)
        }
        .onAppear {
            installGotoObserver()
            applyPendingGoto()
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
            applyPendingGoto()
        }
    }

    private func sendCommand() {
        let cmd = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        forth.send(.executeCommand(command: cmd))
        commandLine = ""
    }

    private func applyPendingGoto() {
        if let line = PendingGoto.consumeIfMatches(documentPath: fileURL?.path) {
            gotoLine = line
        }
    }

    private func installGotoObserver() {
        guard gotoObserver == nil else { return }
        gotoObserver = DistributedNotificationCenter.default().addObserver(
            forName: PendingGoto.notificationName,
            object: nil,
            queue: .main
        ) { note in
            guard let info = note.userInfo,
                  let path = info["path"] as? String,
                  let line = info["line"] as? Int,
                  line > 0,
                  let url = fileURL,
                  PendingGoto.pathsMatch(url.path, path)
            else {
                applyPendingGoto()
                return
            }
            _ = PendingGoto.consume()
            gotoLine = line
        }
    }
}

#Preview {
    ContentView(document: .constant(ForthDocument()), fileURL: nil)
        .environmentObject(ForthConnectionManager())
}
