//
//  WorkspaceModel.swift
//  64Edit
//
//  Single-window tab workspace (Slice 1). Replaces DocumentGroup so one shared
//  Forth console can serve every open file.
//

import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

/// One open editor buffer (path optional until first Save As).
final class EditorTab: Identifiable, ObservableObject {
    let id = UUID()
    @Published var text: String
    @Published var fileURL: URL?
    @Published var isDirty: Bool
    @Published var isViewMode: Bool
    @Published var gotoLine: Int?
    /// Caret / selection restored when this tab becomes selected again.
    var selection = NSRange(location: 0, length: 0)
    /// 1-based first visible line restored with the selection (not @Published — caret churn).
    var topVisibleLine: Int = 1

    init(
        text: String = "",
        fileURL: URL? = nil,
        isDirty: Bool = false,
        isViewMode: Bool = false,
        gotoLine: Int? = nil
    ) {
        self.text = text
        self.fileURL = fileURL
        self.isDirty = isDirty
        self.isViewMode = isViewMode
        self.gotoLine = gotoLine
    }

    var title: String {
        let name = fileURL?.lastPathComponent ?? "Untitled"
        return isDirty ? "\(name) •" : name
    }

    var pathString: String? { fileURL?.path }
}

/// Owns the open-tab list and find-or-open for VIEW / EDIT / debugLocation.
final class WorkspaceModel: ObservableObject {
    @Published private(set) var tabs: [EditorTab] = []
    @Published var selectedTabID: UUID?

    private var tabCancellables: [UUID: AnyCancellable] = [:]

    var selectedTab: EditorTab? {
        tabs.first { $0.id == selectedTabID }
    }

    // MARK: - Open / focus

    /// Open `url` or select an existing tab for the same path/inode.
    /// `viewMode` nil keeps an existing tab's mode (and defaults new tabs to edit);
    /// true/false forces VIEW or EDIT. `open -a` must pass nil so it does not
    /// clobber VIEW/debug browse mode after pending-goto was already consumed.
    @discardableResult
    func openURL(
        _ url: URL,
        viewMode: Bool? = nil,
        line: Int? = nil,
        reloadIfClean: Bool = false
    ) -> EditorTab? {
        let standardized = url.standardizedFileURL
        if let existing = findTab(matching: standardized.path) {
            focus(existing, viewMode: viewMode, line: line, reloadIfClean: reloadIfClean, fileURL: standardized)
            return existing
        }

        // Relative VIEW stamps (Library/…, AutoLoad/…) must not create a second empty tab
        // beside an already-open absolute copy of the same leaf.
        let exists = FileManager.default.fileExists(atPath: standardized.path)
        if !exists {
            let leaf = standardized.lastPathComponent
            if let byLeaf = tabForLeaf(leaf) {
                focus(byLeaf, viewMode: viewMode, line: line, reloadIfClean: false, fileURL: nil)
                return byLeaf
            }
            return nil
        }

        let text = Self.readFile(standardized) ?? ""
        let tab = EditorTab(
            text: text,
            fileURL: standardized,
            isDirty: false,
            isViewMode: viewMode ?? false,
            gotoLine: (line ?? 0) > 0 ? line : nil
        )
        insertTab(tab)
        selectedTabID = tab.id
        return tab
    }

    /// Finder / `open -a` delivery. Does not force edit mode — pending-goto,
    /// sock debugLocation, or Open panel set mode explicitly.
    func openExternalURLs(_ urls: [URL]) {
        for url in urls {
            guard url.isFileURL else { continue }
            openURL(url, viewMode: nil, line: nil)
        }
        // pending-goto may refine view mode / line for the last opened path.
        handlePendingGoto()
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText, .text, .utf8PlainText, .forthSource]
        panel.prompt = "Open"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            // File menu Open always unlocks editing.
            openURL(url, viewMode: false, line: nil)
        }
    }

    // MARK: - Save

    @discardableResult
    func saveSelected() -> Bool {
        guard let tab = selectedTab else { return false }
        if let url = tab.fileURL {
            return write(tab, to: url)
        }
        return saveSelectedAs()
    }

    @discardableResult
    func saveSelectedAs() -> Bool {
        guard let tab = selectedTab else { return false }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText, .utf8PlainText, .forthSource]
        panel.canCreateDirectories = true
        panel.title = "Save As"
        if let url = tab.fileURL {
            panel.directoryURL = url.deletingLastPathComponent()
            panel.nameFieldStringValue = url.lastPathComponent
        } else {
            panel.nameFieldStringValue = "Untitled.fth"
        }
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return write(tab, to: url.standardizedFileURL)
    }

    // MARK: - Close / new

    func closeSelected() {
        guard let id = selectedTabID else { return }
        closeTab(id: id)
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabCancellables[id] = nil
        tabs.remove(at: index)
        if selectedTabID == id {
            if tabs.isEmpty {
                selectedTabID = nil
            } else {
                let next = min(index, tabs.count - 1)
                selectedTabID = tabs[next].id
            }
        }
        objectWillChange.send()
    }

    /// Minimal untitled buffer so the window is never empty after close-all.
    func newUntitledIfEmpty() {
        guard tabs.isEmpty else { return }
        let tab = EditorTab(text: "", fileURL: nil, isDirty: false)
        insertTab(tab)
        selectedTabID = tab.id
    }

    // MARK: - Pending goto / debug

    /// Consume pending-goto.json and find-or-open the path (any window/tab).
    func handlePendingGoto() {
        guard let pending = PendingGoto.peek() else { return }
        openURL(
            URL(fileURLWithPath: pending.path),
            viewMode: pending.viewMode,
            line: pending.line > 0 ? pending.line : nil
        )
        _ = PendingGoto.consume()
    }

    func applyDebugLocation(path: String, line: Int) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let existing = findTab(matching: trimmed) {
            focus(existing, viewMode: true, line: line > 0 ? line : nil, reloadIfClean: false, fileURL: nil)
            return
        }
        _ = openURL(
            URL(fileURLWithPath: trimmed),
            viewMode: true,
            line: line > 0 ? line : nil
        )
    }

    // MARK: - Internals

    private func findTab(matching path: String) -> EditorTab? {
        tabs.first { tab in
            guard let p = tab.pathString else { return false }
            return PendingGoto.pathsMatch(p, path)
        }
    }

    /// Prefer a tab whose file still exists on disk (avoids focusing a stale empty twin).
    private func tabForLeaf(_ leaf: String) -> EditorTab? {
        let matches = tabs.filter { $0.fileURL?.lastPathComponent == leaf }
        if let real = matches.first(where: { tab in
            guard let p = tab.pathString else { return false }
            return FileManager.default.fileExists(atPath: p)
        }) {
            return real
        }
        return matches.first(where: { !$0.text.isEmpty }) ?? matches.first
    }

    private func focus(
        _ tab: EditorTab,
        viewMode: Bool?,
        line: Int?,
        reloadIfClean: Bool,
        fileURL: URL?
    ) {
        selectedTabID = tab.id
        // nil = preserve (open -a must not strip VIEW/debug browse mode).
        if let viewMode {
            tab.isViewMode = viewMode
        }
        if let line, line > 0 {
            tab.gotoLine = line
        }
        if let fileURL, tab.fileURL == nil {
            tab.fileURL = fileURL
        }
        if reloadIfClean, !tab.isDirty, let fileURL,
           let text = Self.readFile(fileURL) {
            tab.text = text
        }
    }

    private func insertTab(_ tab: EditorTab) {
        tabs.append(tab)
        tabCancellables[tab.id] = tab.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        objectWillChange.send()
    }

    private func write(_ tab: EditorTab, to url: URL) -> Bool {
        do {
            try tab.text.data(using: .utf8)?.write(to: url, options: .atomic)
            tab.fileURL = url
            tab.isDirty = false
            objectWillChange.send()
            return true
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            return false
        }
    }

    private static func readFile(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }
}
