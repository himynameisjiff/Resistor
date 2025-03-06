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
        let height = cgImage.height

        // The Y position for the middle row of the screen
        let middleY = height / 2

        // Define the region: scan the entire row at the middleY position
        let region = CGRect(x: 0, y: middleY, width: width, height: 1)

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

            // Convert RGBA to HSV
            let (h, s, v, _) = rgbaToHsv(r: r, g: g, b: b, a: a)

            // If this pixel color is different from the last one and is not similar, print it
            if let lastColor = lastColor {
                if !isColorSimilar(lastColor, (r, g, b, a), tolerance: tolerance) {
                    // Print the new color in HSV
                    print("Pixel at (\(x), \(middleY)): H: \(h), S: \(s), V: \(v)")
                }
            } else {
                // Print the very first color in HSV
                print("Pixel at (\(x), \(middleY)): H: \(h), S: \(s), V: \(v)")
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

    func rgbaToHsv(r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> (h: CGFloat, s: CGFloat, v: CGFloat, a: CGFloat) {
        let rf = CGFloat(r) / 255.0
        let gf = CGFloat(g) / 255.0
        let bf = CGFloat(b) / 255.0
        let af = CGFloat(a) / 255.0

        let maxVal = max(rf, gf, bf)
        let minVal = min(rf, gf, bf)
        let delta = maxVal - minVal

        var h: CGFloat = 0
        var s: CGFloat = 0
        let v: CGFloat = maxVal

        if maxVal != 0 {
            s = delta / maxVal
        } else {
            s = 0
            h = 0
            return (h, s, v, af)
        }

        if rf == maxVal {
            h = (gf - bf) / delta
        } else if gf == maxVal {
            h = 2 + (bf - rf) / delta
        } else {
            h = 4 + (rf - gf) / delta
        }

        h *= 60
        if h < 0 {
            h += 360
        }

        return (h, s, v, af)
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
