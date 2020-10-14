//
//  ProcessVideoFileViewController.swift
//  ObjectDetection
//
//  Created by Derek Tseng on 2020/10/13.
//  Copyright © 2020 MachineThink. All rights reserved.
//

import UIKit
import CoreMedia
import CoreML
import Vision

class ProcessVideoFileViewController: UIViewController {

    var videoFileCapture: VideoFileCapture!

    var currentBuffer: CVPixelBuffer?

    var currentSampleBuffer: CMSampleBuffer?  // Remove if object marking is implemented

    let coreMLModel = MobileNetV2_SSDLite()

    var recording = false

    var recorder = EventVideoProducer()

    @IBOutlet var videoPreview: UIView!

    lazy var visionModel: VNCoreMLModel = {
        do {
            return try VNCoreMLModel(for: coreMLModel.model)
        } catch {
            fatalError("Failed to create VNCoreMLModel: \(error)")
        }
    }()

    lazy var visionRequest: VNCoreMLRequest = {
        let request = VNCoreMLRequest(model: visionModel, completionHandler: {
            [weak self] request, error in
            self?.processObservations(for: request, error: error)
        })

        // NOTE: If you use another crop/scale option, you must also change
        // how the BoundingBoxView objects get scaled when they are drawn.
        // Currently they assume the full input image is used.
        request.imageCropAndScaleOption = .scaleFill
        return request
    }()

    private lazy var boundingBoxView = {
        return BoundingBoxView()
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        let filePath = Bundle.main.path(forResource: "video", ofType: "mp4")!
        videoFileCapture = VideoFileCapture(fileURL: URL(fileURLWithPath: filePath))
        videoFileCapture.delegate = self
        videoFileCapture.processFrames()
    }

    func predict(sampleBuffer: CMSampleBuffer) {
      currentSampleBuffer = sampleBuffer

      if currentBuffer == nil, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
        currentBuffer = pixelBuffer

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        DispatchQueue.global(qos: .userInitiated).sync {
            do {
              try handler.perform([self.visionRequest])
            } catch {
              print("Failed to perform Vision request: \(error)")
            }
        }

        currentBuffer = nil
      }
    }


    func processObservations(for request: VNRequest, error: Error?) {
        if let results = request.results as? [VNRecognizedObjectObservation], let sampleBuffer = currentSampleBuffer {
            let personResults = results.filter { (observation) -> Bool in
                observation.labels.first?.identifier == "person"
            }

            if !recording && !personResults.isEmpty {
                recording = true
            }

            if !personResults.isEmpty, let pixelBuffer = currentBuffer {
                // Draw marker
                // Lock pixelBuffer to start adding mask on it
                CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

                defer {
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
                }

                //Deep copy buffer pixel to avoid memory leak
                var processedPixelBuffer: CVPixelBuffer? = nil
                let options = [
                    kCVPixelBufferCGImageCompatibilityKey as String: true,
                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                ] as CFDictionary

                let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                                 CVPixelBufferGetWidth(pixelBuffer),
                                                 CVPixelBufferGetHeight(pixelBuffer),
                                                 kCVPixelFormatType_32BGRA, options,
                                                 &processedPixelBuffer)
                guard status == kCVReturnSuccess else { return }

                // Lock destination buffer until we finish the drawing
                CVPixelBufferLockBaseAddress(processedPixelBuffer!,
                                             CVPixelBufferLockFlags(rawValue: 0))

                defer {
                    CVPixelBufferUnlockBaseAddress(processedPixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
                }

                guard let processedPixelBufferUnwrapped = processedPixelBuffer,
                    let processedPixelBufferBaseAddress = CVPixelBufferGetBaseAddress(processedPixelBuffer!)
                else {
                    return
                }

                memcpy(processedPixelBufferBaseAddress,
                       CVPixelBufferGetBaseAddress(pixelBuffer),
                       CVPixelBufferGetHeight(pixelBuffer) * CVPixelBufferGetBytesPerRow(pixelBuffer))

                let width = CVPixelBufferGetWidth(processedPixelBufferUnwrapped)
                let height = CVPixelBufferGetHeight(processedPixelBufferUnwrapped)
                let bytesPerRow = CVPixelBufferGetBytesPerRow(processedPixelBufferUnwrapped)
                let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue))  // Need to cache
                let colorSpace = CGColorSpaceCreateDeviceRGB()  // Need to cache
                guard let context = CGContext(data: processedPixelBufferBaseAddress,
                                        width: width,
                                        height: height,
                                        bitsPerComponent: 8,
                                        bytesPerRow: bytesPerRow,
                                        space: colorSpace,
                                        bitmapInfo: bitmapInfo.rawValue)
                else { return }

                // Draw
                let scale = CGAffineTransform.identity.scaledBy(x: CGFloat(width), y: CGFloat(height))

                // Show the bounding box for each object
                for feature in personResults {
                    let label = String(format: "Person %.1f", feature.confidence * 100)
                    let color = UIColor.red
                    let rect = feature.boundingBox.applying(scale)
                    let boundingBoxLayers = boundingBoxView.getLayers(frame: rect, label: label, color: color)
                    boundingBoxLayers.shapeLayer.render(in: context)
                    context.translateBy(x: rect.origin.x, y: rect.origin.y)
                    boundingBoxLayers.textLayer.render(in: context)
                }

                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                if !recorder.appendSampleBuffer(buffer: processedPixelBufferUnwrapped, timestamp: timestamp) {
                    recorder.saveFile()
                    // Video duration has a 10 seconds limit
                    // Trigger another recording for this new detection
                    recorder = EventVideoProducer()
                    recorder.appendSampleBuffer(buffer: processedPixelBufferUnwrapped, timestamp: timestamp)
                }
            } else if recording, let buffer = currentBuffer {
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                if !recorder.appendSampleBuffer(buffer: buffer, timestamp: timestamp) {
                    // Discard this buffer and stop recording due to 10 sec limit
                    recorder.saveFile()
                    recording = false
                }
            }
        }
    }

}

extension ProcessVideoFileViewController: VideoFileCaptureDelegate {

    func videoFileCapture(_ capture: VideoFileCapture, didCaptureVideoFrame sampleBuffer: CMSampleBuffer) {
//        if recording {
//            // TODO: Process object marking
//            if !recorder.appendSampleBuffer(buffer: sampleBuffer) {
//                recorder.saveFile()
//                recorder = EventVideoProducer()
//                predict(sampleBuffer: sampleBuffer)
//            }
//        } else {
//            predict(sampleBuffer: sampleBuffer)
//        }
        predict(sampleBuffer: sampleBuffer)
    }

    func videoFileCaptureFinished(_ capture: VideoFileCapture) {
        // Finalize last recording if there is one
        if recorder.hasData {
            recorder.saveFile()
            recording = false
        }
    }

}
