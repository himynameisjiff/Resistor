//
//  EdgeDetection.swift
//  Resistor
//
//  Created by Prahalad on 3/12/25.
//

import Foundation
import UIKit
import CoreImage

class EdgeDetector {
    private let context = CIContext()

    func detectVerticalEdges(in image: UIImage) -> [Int]? {
        guard let ciImage = CIImage(image: image) else { return nil }

        // Apply edge detection filter
        let edgesImage = ciImage.applyingFilter("CISobelEdgeDetection", parameters: ["inputIntensity": 1.0])

        // Convert to grayscale for easier processing
        let grayscaleImage = edgesImage.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            kCIInputContrastKey: 2.0
        ])

        // Convert CIImage to CGImage
        guard let cgImage = context.createCGImage(grayscaleImage, from: grayscaleImage.extent) else { return nil }

        // Process image data to detect vertical edges
        return findEdgePositions(in: cgImage)
    }

    private func findEdgePositions(in cgImage: CGImage) -> [Int] {
        let width = cgImage.width
        let height = cgImage.height

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerPixel = 1
        let bytesPerRow = width * bytesPerPixel
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: height * bytesPerRow)
        defer { buffer.deallocate() }

        guard let context = CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return [] }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let middleRow = height / 2
        var edges: [Int] = []

        for x in 1..<width {
            let prevPixel = buffer[middleRow * bytesPerRow + (x - 1)]
            let currPixel = buffer[middleRow * bytesPerRow + x]

            if abs(Int(currPixel) - Int(prevPixel)) > 50 { // Threshold for edge detection
                edges.append(x)
            }
        }

        return edges
    }
}
