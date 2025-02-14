//
//  FrameHandler.swift
//  Resistor
//
//  Created by Prahalad on 2/11/25.
//
import AVFoundation
import CoreImage
import Foundation
import UIKit
class FrameHandler: NSObject, ObservableObject {
    @Published var frame: CGImage?
    private var permissionGranted = false
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private let context = CIContext()

    override init() {
        super.init()
        checkPermission()
        sessionQueue.async {
            [unowned self] in self.setupCaptureSession()
            self.captureSession.startRunning()
        }
    }
    
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
        case .notDetermined:
            requestPermission()
        default:
            permissionGranted = false
        }
    }

    func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [unowned self] granted in
            self.permissionGranted = granted
        }
    }

    func setupCaptureSession() {
        let videoOutput = AVCaptureVideoDataOutput()
        
        guard permissionGranted else { return }
        guard let videoDevice = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) else { return }
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
        guard captureSession.canAddInput(videoDeviceInput) else { return }
        captureSession.addInput(videoDeviceInput)
        
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sampleBufferQueue"))
        captureSession.addOutput(videoOutput)
        videoOutput.connection(with: .video)?.videoRotationAngle = 90
    }

    func extractColors() {
        guard let cgImage = frame else { return }

        let width = cgImage.width

        // The Y position for the black line center from the ContentView
        // This value is set to the center of the screen (rectangleY)
        let rectangleHeight: CGFloat = 10
        let rectangleY = UIScreen.main.bounds.height / 2 - rectangleHeight / 2
        let rectangleYInt = Int(rectangleY)

        // Define the region: scan the entire row at the rectangleY position (where the black line is)
        let region = CGRect(x: 0, y: rectangleYInt, width: width, height: 1)

        // Convert the CGImage to a CIImage
        let ciImage = CIImage(cgImage: cgImage)

        // Extract pixel data from the defined region
        guard let cgImageRegion = context.createCGImage(ciImage, from: region) else { return }

        // Create a bitmap context to read pixel data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = cgImageRegion.width * 4 // 4 bytes per pixel (RGBA)
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: cgImageRegion.width * bytesPerRow)
        guard let context = CGContext(data: data, width: cgImageRegion.width, height: cgImageRegion.height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }

        context.draw(cgImageRegion, in: CGRect(x: 0, y: 0, width: cgImageRegion.width, height: cgImageRegion.height))

        var lastColor: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? = nil
        let tolerance: UInt8 = 10 // Define an acceptable range of color difference

        // Loop through the pixels (this time we only scan one row)
        for x in stride(from: 0, to: cgImageRegion.width, by: 1) {
            let offset = x * 4
            let r = data[offset]
            let g = data[offset + 1]
            let b = data[offset + 2]
            let a = data[offset + 3]

            // If this pixel color is different from the last one and is not similar, print it
            if let lastColor = lastColor {
                if !isColorSimilar(lastColor, (r, g, b, a), tolerance: tolerance) {
                    // Print the new color
                    print("Pixel at (\(x), \(rectangleYInt)): R: \(r), G: \(g), B: \(b), A: \(a)")
                }
            } else {
                // Print the very first color
                print("Pixel at (\(x), \(rectangleYInt)): R: \(r), G: \(g), B: \(b), A: \(a)")
            }

            // Store the current color for comparison with the next pixel
            lastColor = (r, g, b, a)
        }

        data.deallocate()
    }
    
    func isColorSimilar(_ color1: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ color2: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), tolerance: UInt8 = 10) -> Bool {
        let rDiff = abs(Int(color1.r) - Int(color2.r))
        let gDiff = abs(Int(color1.g) - Int(color2.g))
        let bDiff = abs(Int(color1.b) - Int(color2.b))

        // Check if the difference in each color component is within the allowed tolerance
        return rDiff <= Int(tolerance) && gDiff <= Int(tolerance) && bDiff <= Int(tolerance)
    }
}

extension FrameHandler: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let cgImage = imageFromSampleBuffer(sampleBuffer: sampleBuffer) else { return }

        DispatchQueue.main.async { [unowned self] in
            self.frame = cgImage
        }
    }

    private func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> CGImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        
        return cgImage
    }
}
