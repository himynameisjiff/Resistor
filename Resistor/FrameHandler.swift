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
import CoreML
class FrameHandler: NSObject, ObservableObject {
    @Published var frame: CGImage?
    @Published var scannedRow: CGImage?
    @Published var array: [String]?
    @Published var edgePositions: [Int] = []
    private var permissionGranted = false
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private let context = CIContext()
    private let edgeDetector = EdgeDetector()

    override init() {
        super.init()
        checkPermission()
        sessionQueue.async { [unowned self] in
            self.setupCaptureSession()
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

    /// Extracts the region corresponding to the displayed scanning rectangle in FrameView,
    /// then further crops it so that only 25% to 75% of the row is shown.
    ///
    /// The FrameView displays the camera image scaled to 300×200.
    /// The scanning rectangle is drawn with size 296×10 and centered in the view.
    /// This function computes the equivalent region in the full resolution image,
    /// then crops the resulting row to the central 50% of its width.
    /// Finally, it runs the color detection algorithm, which prints out the unique color names, in order,
    /// adding a new color only when it is different than the previous one.
    func extractColors() {
        guard let cgImage = frame else { return }
        
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        
        let frameViewWidth: CGFloat = 300
        let frameViewHeight: CGFloat = 200
        
        let scaleX = imageWidth / frameViewWidth
        let scaleY = imageHeight / frameViewHeight
        
        let scanningRectWidth: CGFloat = 296
        let scanningRectHeight: CGFloat = 10
        let rectOriginX: CGFloat = (frameViewWidth - scanningRectWidth) / 2
        let rectOriginY: CGFloat = (frameViewHeight - scanningRectHeight) / 2
        
        let imageRectOriginX = rectOriginX * scaleX
        let imageRectOriginY = rectOriginY * scaleY
        let imageRectWidth = scanningRectWidth * scaleX
        let imageRectHeight = scanningRectHeight * scaleY
        
        let cropRect = CGRect(x: imageRectOriginX, y: imageRectOriginY, width: imageRectWidth, height: imageRectHeight)
        
        let ciImage = CIImage(cgImage: cgImage).cropped(to: cropRect)
        
        // Further crop to the central 50% of row width
        let furtherCropOriginX = ciImage.extent.origin.x + ciImage.extent.width * 0.2
        let furtherCropWidth = ciImage.extent.width * 0.6
        let furtherCropRect = CGRect(x: furtherCropOriginX,
                                     y: ciImage.extent.origin.y,
                                     width: furtherCropWidth,
                                     height: ciImage.extent.height)
        let croppedCIImage = ciImage.cropped(to: furtherCropRect)

        // Step 1: Apply Noise Reduction (CIMedianFilter)
        let noiseReducedImage = croppedCIImage.applyingFilter("CINoiseReduction")

        // Step 2: Sharpen Image (Unsharp Mask)
        let sharpenedImage = noiseReducedImage.applyingFilter("CIUnsharpMask", parameters: [
            "inputRadius": 3.0,  // Controls the extent of sharpening
            "inputIntensity": 1.0
        ])
        //let contrastEnhanced = noiseReducedImage.applyingFilter("CIHighlightShadiwAdjust", parameters:[
         //   "inputHighlightAmount": 0.9,
          //  "inputShadowAmount": 0.1
        //])
        // Step 3: Adjust Contrast & Saturation
        let finalProcessedImage = sharpenedImage.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: 0,
            kCIInputContrastKey: 1.3,
            kCIInputSaturationKey: 2.0
        ])

        // Convert to CGImage for display
        guard let newCGImage = context.createCGImage(finalProcessedImage, from: finalProcessedImage.extent) else { return }

        DispatchQueue.main.async {
            self.scannedRow = newCGImage
        }

        detectColors(in: newCGImage)
        detectEdges(on: newCGImage)
        print(self.edgePositions)
    }
    
    func detectEdges(on cgImage: CGImage) {
        let uiImage = UIImage(cgImage: cgImage)
        if let edgePositions = edgeDetector.detectVerticalEdges(in: uiImage) {
            DispatchQueue.main.async {
                self.edgePositions = edgePositions
                print("Detected Edge Positions:", edgePositions)
            }
        }
    }
    /// Detects colors from the provided CGImage and prints the unique color names in order,
    /// adding a new color only when it is different than the previous one.
    func detectColors(in cgImage: CGImage) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = cgImage.width * bytesPerPixel
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: cgImage.height * bytesPerRow)
        defer { data.deallocate() }
        
        guard let bitmapContext = CGContext(data: data,
                                            width: cgImage.width,
                                            height: cgImage.height,
                                            bitsPerComponent: 8,
                                            bytesPerRow: bytesPerRow,
                                            space: colorSpace,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        
        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        
        let middleRow = cgImage.height / 2
        // Store color names in order, adding a new color only when it is different than the previous one.
        var colorNames: [String] = []
        var previousColor: String? = nil
        
        // Loop through each pixel along the width of the scanned row.
        for x in 0..<cgImage.width {
            let offset = middleRow * bytesPerRow + x * bytesPerPixel
            let r = data[offset]
            let g = data[offset + 1]
            let b = data[offset + 2]
            let a = data[offset + 3]
            
            let hsv = rgbaToHsv(r: r, g: g, b: b, a: a)
            let colorName = getColorName(from: hsv)
            print("R:\(r), G:\(g), B:\(b)")
            if previousColor != colorName {
                colorNames.append(colorName)
            }
            previousColor = colorName
        }
        
        // Print the ordered list of unique color names.
        self.array = colorNames
        print("Ordered Unique Colors Detected:")
        print(colorNames)
    }
    
    /// Returns the color name based on the HSV values according to the provided ranges.
    func getColorName(from hsv: (h: CGFloat, s: CGFloat, v: CGFloat, a: CGFloat)) -> String {
        // Check for white/gray first (low saturation)
        if hsv.s <= 10 {
            if hsv.v >= 80 {
                return "White"
            } //else if hsv.v >= 30 && hsv.v < 70 {
            //    return "Gray"
            //}
        }
        
        // Check for black (very low brightness)
        if hsv.v < 20 {
            return "Black"
        }
        
        if hsv.h >= 20 && hsv.h <= 30 && hsv.s >= 50 && hsv.s <= 100 && hsv.v >= 30 && hsv.v <= 60 {
            return "Brown"
        }
        if hsv.h >= 0 && hsv.h <= 10 && hsv.s >= 80 && hsv.s <= 100 && hsv.v >= 50 && hsv.v <= 100 {
            return "Red"
        }
        if hsv.h >= 30 && hsv.h <= 40 && hsv.s >= 80 && hsv.s <= 100 && hsv.v >= 50 && hsv.v <= 100 {
            return "Orange"
        }
        if hsv.h >= 50 && hsv.h <= 60 && hsv.s >= 80 && hsv.s <= 100 && hsv.v >= 60 && hsv.v <= 100 {
            return "Yellow"
        }
        if hsv.h >= 90 && hsv.h <= 140 && hsv.s >= 60 && hsv.s <= 100 && hsv.v >= 30 && hsv.v <= 90 {
            return "Green"
        }
        if hsv.h >= 200 && hsv.h <= 240 && hsv.s >= 50 && hsv.s <= 100 && hsv.v >= 30 && hsv.v <= 100 {
            return "Blue"
        }
        if hsv.h >= 270 && hsv.h <= 325 && hsv.s >= 50 && hsv.s <= 100 && hsv.v >= 30 && hsv.v <= 100 {
            return "Violet"
        }
        //if hsv.h >= 40 && hsv.h <= 60 && hsv.s >= 40 && hsv.s <= 80 && hsv.v >= 50 && hsv.v <= 90 {
        //    return "Gold"
        //}
        //if hsv.h >= 200 && hsv.h <= 220 && hsv.s >= 10 && hsv.s <= 40 && hsv.v >= 70 && hsv.v <= 90 {
        //    return "Silver"
        // }
        
        return "White"
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
        let v: CGFloat = maxVal * 100
        
        if maxVal != 0 {
            s = (delta / maxVal) * 100
        } else {
            s = 0
            return (h, s, v, af)
        }
        
        if maxVal == minVal {
            h = 0
        } else {
            if rf == maxVal {
                h = fmod(60 * ((gf - bf) / delta) + 360, 360)
            } else if gf == maxVal {
                h = fmod(60 * ((bf - rf) / delta) + 120, 360)
            } else if bf == maxVal {
                h = fmod(60 * ((rf - gf) / delta) + 240, 360)
            }
        }
        
        return (h, s, v, af)
    }
    func getColors(in cimage: CGImage) -> String{
        let label = ""
        let imageClassifierWrapper = try? Resistor_Classifier_1(configuration: MLModelConfiguration())
        if let colors = try? imageClassifierWrapper?.prediction(image: (cgImageToPixelBuffer(cimage))!){
            let label = colors.target
        }
        return label
    }
            func cgImageToPixelBuffer(_ image: CGImage) -> CVPixelBuffer? {
                let width = image.width
                let height = image.height

                let attrs: [CFString: Any] = [
                    kCVPixelBufferCGImageCompatibilityKey: true,
                    kCVPixelBufferCGBitmapContextCompatibilityKey: true
                ]
                
                var pixelBuffer: CVPixelBuffer?
                let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                                 width,
                                                 height,
                                                 kCVPixelFormatType_32ARGB, // Ensure the correct format
                                                 attrs as CFDictionary,
                                                 &pixelBuffer)
                
                guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                    return nil
                }

                CVPixelBufferLockBaseAddress(buffer, [])
                guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                              width: width,
                                              height: height,
                                              bitsPerComponent: 8,
                                              bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
                    CVPixelBufferUnlockBaseAddress(buffer, [])
                    return nil
                }

                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                CVPixelBufferUnlockBaseAddress(buffer, [])

                return buffer
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
