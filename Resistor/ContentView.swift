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
        ZStack {
            // Black background
            Color.black
                .ignoresSafeArea() // Fills the entire screen with black
            
            // Centered frame with a rounded rectangle cutout
            FrameView(image: model.frame)
                .frame(width: 300, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 25))
                .overlay(RoundedRectangle(cornerRadius: 25).stroke(Color.white, lineWidth: 4))
                .shadow(radius: 10)
                .position(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2)
            
            Rectangle()
                .frame(width: 296, height: 10)
                .foregroundColor(.black.opacity(0.5))
                .position(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2)
            Rectangle()
                .frame(width:10, height: 10)
                .foregroundColor(.red)
                .position(x: 48.5,y:426)
            Rectangle()
                .frame(width:10, height: 10)
                .foregroundColor(.red)
                .position(x: 344.5,y:426)
            // Button to scan the colors
            VStack {
                Spacer()
                Button("Scan Colors") {
                    model.extractColors() // Trigger color extraction
                }
                .padding()
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(8)
                .shadow(radius: 5)
            }
        }
    }
}

struct ContentView_Preview: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
