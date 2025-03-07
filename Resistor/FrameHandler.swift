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

        // Define the specific region from (48,426) to (345,426)
        let startX = 48
        let endX = 345
        let scanWidth = endX - startX
        let scanY = 426

        // Ensure the scan area is within the image bounds
        guard startX >= 0, scanWidth > 0, scanY >= 0, scanY < height, endX <= width else { return }

        let region = CGRect(x: startX, y: scanY, width: scanWidth, height: 1)

        // Convert CGImage to CIImage and apply filters
        let ciImage = CIImage(cgImage: cgImage).applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: 0.2,  // Increase brightness slightly
            kCIInputContrastKey: 1.5,    // Enhance contrast
            kCIInputSaturationKey: 2.0   // Increase saturation (adjust as needed)
        ])

        let ciContext = CIContext()
        guard let cgImageRegion = ciContext.createCGImage(ciImage, from: region) else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = cgImageRegion.width * bytesPerPixel
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: cgImageRegion.width * bytesPerPixel)

        defer { data.deallocate() } // Ensure memory is freed

        guard let bitmapContext = CGContext(data: data, width: cgImageRegion.width, height: cgImageRegion.height,
                                            bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }

        bitmapContext.draw(cgImageRegion, in: CGRect(x: 0, y: 0, width: cgImageRegion.width, height: cgImageRegion.height))

        var lastColor: (h: CGFloat, s: CGFloat, v: CGFloat, a: CGFloat)? = nil
        let tolerance: CGFloat = 5

        for x in 0..<cgImageRegion.width {
            let offset = x * bytesPerPixel
            let r = data[offset]
            let g = data[offset + 1]
            let b = data[offset + 2]
            let a = data[offset + 3]

            let hsv = rgbaToHsv(r: r, g: g, b: b, a: a)

            if let lastColor = lastColor {
                if !isColorSimilar(lastColor, hsv, tolerance: tolerance) {
                    print("Pixel at (\(startX + x), \(scanY)): H: \(hsv.h), S: \(hsv.s), V: \(hsv.v)")
                    print("R: \(r), G: \(g), B: \(b)")
                }
            } else {
                print("Pixel at (\(startX + x), \(scanY)): H: \(hsv.h), S: \(hsv.s), V: \(hsv.v)")
                print("R: \(r), G: \(g), B: \(b)")
            }

            lastColor = hsv
        }
    }

    
    func isColorSimilar(_ color1: (h: CGFloat, s: CGFloat, v: CGFloat, a: CGFloat), _ color2: (h: CGFloat, s: CGFloat, v: CGFloat, a: CGFloat), tolerance: CGFloat = 1) -> Bool {
        let rDiff = min(abs(color1.h - color2.h), 360 - abs(color1.h - color2.h))

        // Check if the difference in each color component is within the allowed tolerance
        return rDiff <= tolerance
    }

    func rgbaToHsv(r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> (h: CGFloat, s: CGFloat, v: CGFloat, a: CGFloat) {
        let rf = CGFloat(r) / 255.0
        let gf = CGFloat(g) / 255.0
        let bf = CGFloat(b) / 255.0
        let af = CGFloat(a) / 255.0

        let maxVal = max(rf, gf, bf)
        let minVal = min(rf, gf, bf)
        let delta = maxVal - minVal

        var h: CGFloat = -1
        var s: CGFloat = -1
        let v: CGFloat = maxVal*100

        if (maxVal==minVal) {
            h = 0;
        }
        else if rf == maxVal {
            h = fmod(60 * ((gf-bf) / delta) + 360, 360)
        } else if gf == maxVal {
            h = fmod(60 * ((bf - rf) / delta) + 120, 360)
        } else {
            h = fmod(60 * ((rf - gf) / delta) + 240, 360);
        }

        if maxVal != 0 {
            s = (delta / maxVal) * 100
        } else {
            s = 0
            return (h, s, v, af)
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
