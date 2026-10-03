//
//  AppDelegate.swift
//  64Edit
//
//  Receives Finder / `open -a 64Edit.app path` file opens for the tab workspace.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var workspace: WorkspaceModel?
    private var queuedURLs: [URL] = []

    func attach(workspace: WorkspaceModel) {
        self.workspace = workspace
        let urls = queuedURLs
        queuedURLs = []
        if !urls.isEmpty {
            workspace.openExternalURLs(urls)
        } else {
            workspace.handlePendingGoto()
        }
        if workspace.tabs.isEmpty {
            workspace.newUntitledIfEmpty()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let workspace {
            workspace.openExternalURLs(urls)
        } else {
            queuedURLs.append(contentsOf: urls)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }
}
