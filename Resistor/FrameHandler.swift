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

    /// Extracts a row region from the captured frame and publishes it via `scannedRow`.
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

        // Convert CGImage to CIImage and apply color controls filter
        let ciImage = CIImage(cgImage: cgImage).applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: 0.2,  // Increase brightness slightly
            kCIInputContrastKey: 1.5,    // Enhance contrast
            kCIInputSaturationKey: 2.0   // Increase saturation
        ])
        let transform = CGAffineTransform(rotationAngle: .pi/2)
        let rotatedImage = ciImage.transformed(by: transform)
        
        let ciContext = CIContext()
        let newExtenet = rotatedImage.extent
        guard let cgImageRegion = ciContext.createCGImage(rotatedImage, from: newExtenet) else { return }
        
        // Publish the extracted row on the main thread
        DispatchQueue.main.async {
            self.scannedRow = cgImageRegion
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
