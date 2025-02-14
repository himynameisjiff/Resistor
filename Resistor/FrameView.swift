//
//  FrameView.swift
//  Resistor
//
//  Created by Prahalad on 2/11/25.
//

import SwiftUI

struct FrameView: View {
    var image: CGImage?
    private let label = Text("frame")
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(image, scale: 1.0, orientation: .up, label: label)
            } else {
                Color.black
            }

        }
    }
}

#Preview {
    FrameView()
}
