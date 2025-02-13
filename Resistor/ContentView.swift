//
//  ContentView.swift
//  Resistor
//
//  Created by Prahalad on 2/11/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = FrameHandler()
    var body: some View {
        FrameView(image: model.frame)
            .ignoresSafeArea()
    }
}

    struct ContentView_Preview: PreviewProvider {
        static var previews: some View {
            ContentView()
        }
}
