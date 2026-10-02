//
//  ContentView.swift
//  64Edit
//
//  Created by Tom Zimmer on 9/29/26.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: ForthDocument
    @AppStorage("editorFontSize") private var fontSize = 13.0
    @AppStorage("editorWrap") private var wrapLines = false
    @EnvironmentObject private var forth: ForthConnectionManager
    @State private var commandLine = ""
    
    var body: some View {
        VStack(spacing: 0) {
            EditorTextView(
                text: $document.text,
                fontSize: fontSize,
                wrap: wrapLines
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
    }
    
    private func sendCommand() {
        let cmd = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        forth.send(.executeCommand(command: cmd))
        commandLine = ""
    }
}

#Preview {
    ContentView(document: .constant(ForthDocument()))
        .environmentObject(ForthConnectionManager())
}
