import SwiftUI

struct ContentView: View {
    @StateObject private var model = FrameHandler()

    var body: some View {
        ZStack {
            // Black background
            Color.black
                .ignoresSafeArea() // Fills the entire screen with black
            
            VStack {
                // Display the extracted row above the camera view
                if let scannedRow = model.scannedRow {
                    Image(scannedRow, scale: 1.0, orientation: .up, label: Text("Scanned Row"))
                        .resizable()
                        .frame(height: 30)  // Adjust height as needed
                        .border(Color.white)
                        .padding()
                } else {
                    Text("Scanned row will appear here")
                        .foregroundColor(.white)
                        .padding()
                }

                ZStack {
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
                        .frame(width: 10, height: 10)
                        .foregroundColor(.red)
                        .position(x: 48.5, y: 426)

                    Rectangle()
                        .frame(width: 10, height: 10)
                        .foregroundColor(.red)
                        .position(x: 344.5, y: 426)
                }

                Spacer()

                // Display the detected colors as colored rectangles
                if let colors = model.array, !colors.isEmpty {
                    Text("Detected Colors:")
                        .foregroundColor(.white)
                        .font(.headline)
                        .padding(.top)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(colors, id: \.self) { color in
                                colorRectangle(for: color)
                            }
                        }
                        .padding()
                    }
                }

                // Button to trigger row extraction
                VStack {
                    Button("Scan Row") {
                        model.extractColors() // Trigger extraction of the row region
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

    // Helper function to return a colored rectangle based on the color name
    private func colorRectangle(for color: String) -> some View {
        let uiColor = getColor(from: color)
        return Rectangle()
            .fill(Color(uiColor))
            .frame(width: 40, height: 40)
            .cornerRadius(5)
            .overlay(
                Text(color)
                    .font(.caption)
                    .foregroundColor(.black)
                    .padding(2)
            )
    }

    // Convert color name to SwiftUI Color
    private func getColor(from colorName: String) -> UIColor {
        switch colorName.lowercased() {
        case "black": return .black
        case "white": return .white
        case "gray": return .gray
        case "red": return .red
        case "brown": return UIColor.brown
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "violet": return UIColor.purple
        default: return .clear
        }
    }
}

struct ContentView_Preview: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
