//
//  _4EditApp.swift
//  64Edit
//
//  Created by Tom's MacBook Air on 9/29/26.
//

import SwiftUI

@main
struct _4EditApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: _4EditDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
