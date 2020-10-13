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

    let coreMLModel = MobileNetV2_SSDLite()

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

    func processObservations(for request: VNRequest, error: Error?) {
    }

}

extension ProcessVideoFileViewController: VideoFileCaptureDelegate {

    func videoFileCapture(_ capture: VideoFileCapture, didCaptureVideoFrame: CMSampleBuffer) {
        print("frame captured")
    }

    func videoFileCaptureFinished(_ capture: VideoFileCapture) {
        print("finished")
    }

}
