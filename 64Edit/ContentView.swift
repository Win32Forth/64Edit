//
//  ContentView.swift
//  64Edit
//
//  Created by Tom's MacBook Air on 9/29/26.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: _4EditDocument

    var body: some View {
        TextEditor(text: $document.text)
    }
}

#Preview {
    ContentView(document: .constant(_4EditDocument()))
}
