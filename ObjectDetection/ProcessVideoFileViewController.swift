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
        if let results = request.results as? [VNRecognizedObjectObservation], let sampleBuffer = self.currentSampleBuffer {
            let personResults = results.filter { (observation) -> Bool in
                observation.labels.first?.identifier == "person"
            }
            if !personResults.isEmpty {
                self.recording = true
                self.recorder.appendSampleBuffer(buffer: sampleBuffer)
            }
        }
    }

}

extension ProcessVideoFileViewController: VideoFileCaptureDelegate {

    func videoFileCapture(_ capture: VideoFileCapture, didCaptureVideoFrame sampleBuffer: CMSampleBuffer) {
        if recording {
            // TODO: Process object marking
            if !recorder.appendSampleBuffer(buffer: sampleBuffer) {
                recorder.saveFile()
                recorder = EventVideoProducer()
                predict(sampleBuffer: sampleBuffer)
            }
        } else {
            predict(sampleBuffer: sampleBuffer)
        }
    }

    func videoFileCaptureFinished(_ capture: VideoFileCapture) {
        if recorder.hasData {
            recorder.saveFile()
        }
    }

}
