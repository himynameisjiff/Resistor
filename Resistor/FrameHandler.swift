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
    @Published var scannedRow: CGImage?
    
    private var permissionGranted = false
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private let context = CIContext()

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
    func extractColors() {
        guard let cgImage = frame else { return }
        
        // Get the full image dimensions.
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        
        // FrameView dimensions.
        let frameViewWidth: CGFloat = 300
        let frameViewHeight: CGFloat = 200
        
        // Compute scaling factors between the full image and the FrameView dimensions.
        let scaleX = imageWidth / frameViewWidth
        let scaleY = imageHeight / frameViewHeight
        
        // Scanning rectangle dimensions in FrameView.
        let scanningRectWidth: CGFloat = 296
        let scanningRectHeight: CGFloat = 10
        let rectOriginX: CGFloat = (frameViewWidth - scanningRectWidth) / 2
        let rectOriginY: CGFloat = (frameViewHeight - scanningRectHeight) / 2
        
        // Convert the scanning rectangle to the full image coordinate space.
        let imageRectOriginX = rectOriginX * scaleX
        let imageRectOriginY = rectOriginY * scaleY
        let imageRectWidth = scanningRectWidth * scaleX
        let imageRectHeight = scanningRectHeight * scaleY
        
        let cropRect = CGRect(x: imageRectOriginX, y: imageRectOriginY, width: imageRectWidth, height: imageRectHeight)
        
        // Create a CIImage and crop it to the scanning rectangle.
        let ciImage = CIImage(cgImage: cgImage)
        let croppedCIImage = ciImage.cropped(to: cropRect)
        
        // Further crop the extracted row: show only from 25% to 75% of the row width.
        let furtherCropOriginX = croppedCIImage.extent.origin.x + croppedCIImage.extent.width * 0.25
        let furtherCropWidth = croppedCIImage.extent.width * 0.5
        let furtherCropRect = CGRect(x: furtherCropOriginX,
                                     y: croppedCIImage.extent.origin.y,
                                     width: furtherCropWidth,
                                     height: croppedCIImage.extent.height)
        let finalCIImage = croppedCIImage.cropped(to: furtherCropRect)
        
        // Apply a color controls filter to the final cropped image.
        let filteredCIImage = finalCIImage.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: 0.2,  // Slight brightness increase
            //kCIInputContrastKey: 1.5,    // Enhanced contrast
            kCIInputSaturationKey: 2.0   // Increased saturation
        ])
        
        // Create a new CGImage from the filtered CIImage.
        guard let newCGImage = context.createCGImage(filteredCIImage, from: filteredCIImage.extent) else { return }
        
        // Publish the scanned row on the main thread.
        DispatchQueue.main.async {
            self.scannedRow = newCGImage
        }
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
