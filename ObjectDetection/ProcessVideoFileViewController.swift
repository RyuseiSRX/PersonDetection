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
import AVKit

class ProcessVideoFileViewController: UIViewController {

    @IBOutlet var videoPreview: UIView!

    let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Play the video file or start person detection"
        return label
    }()
    lazy var playButton: UIButton = {
        let button = UIButton.init()
        button.setTitle(" Play video file from app ", for: .normal)
        button.setTitleColor(.blue, for: .normal)
        button.setTitleColor(.gray, for: .disabled)
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.lightGray.cgColor
        button.layer.cornerRadius = 4
        button.layer.masksToBounds = true
        button.addTarget(self, action: #selector(playButtonTouched(_:)), for: .touchUpInside)
        return button
    }()
    lazy var detectButton: UIButton = {
        let button = UIButton.init()
        button.setTitle(" Detect person from video file ", for: .normal)
        button.setTitleColor(.blue, for: .normal)
        button.setTitleColor(.gray, for: .disabled)
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.lightGray.cgColor
        button.layer.cornerRadius = 4
        button.layer.masksToBounds = true
        button.addTarget(self, action: #selector(detectButtonTouched(_:)), for: .touchUpInside)
        return button
    }()
    let progressBar: UIProgressView = {
        let view = UIProgressView()
        view.progressTintColor = .blue
        return view
    }()

    var videoFileCapture: VideoFileCapture!
    var currentBuffer: CVPixelBuffer?
    var currentBufferTimestamp: CMTime?//currentSampleBuffer: CMSampleBuffer?  // Remove if object marking is implemented
    let coreMLModel = MobileNetV2_SSDLite()
    var recording = false
    lazy var recorder: EventVideoRecorder = {
        let recorder = EventVideoRecorder()
        recorder.delegate = self
        return recorder
    }()

    let objectMarkerDrawer = ObjectMarkerDrawer()

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

        videoPreview.backgroundColor = .white

        // Do any additional setup after loading the view.

        progressBar.isHidden = true

        view.addSubview(titleLabel)
        view.addSubview(playButton)
        view.addSubview(detectButton)
        view.addSubview(progressBar)

        setupConstraints()
    }

    private func setupConstraints() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        playButton.translatesAutoresizingMaskIntoConstraints = false
        detectButton.translatesAutoresizingMaskIntoConstraints = false
        progressBar.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 44),
            playButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            detectButton.topAnchor.constraint(equalTo: playButton.bottomAnchor, constant: 44),
            detectButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressBar.topAnchor.constraint(equalTo: detectButton.bottomAnchor, constant: 30),
            progressBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressBar.widthAnchor.constraint(equalToConstant: 200)
        ])
    }

    @objc func playButtonTouched(_ sender: UIButton) {
        let viewController = AVPlayerViewController()
        let filePath = Bundle.main.path(forResource: "video2", ofType: "mp4")!
        viewController.player = AVPlayer(url: URL(fileURLWithPath: filePath))
        present(viewController, animated: true, completion: nil)
    }

    @objc func detectButtonTouched(_ sender: UIButton) {
        playButton.isEnabled = false
        detectButton.isEnabled = false
        progressBar.isHidden = false

        let filePath = Bundle.main.path(forResource: "video2", ofType: "mp4")!
        videoFileCapture = VideoFileCapture(fileURL: URL(fileURLWithPath: filePath))
        videoFileCapture.delegate = self
        recorder = EventVideoRecorder()
        recorder.delegate = self
        videoFileCapture.processFrames()
    }

    func predict(sampleBuffer: CMSampleBuffer) {
        guard currentBuffer == nil, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        // Keep in view controller for vision request handling
        currentBuffer = pixelBuffer
        currentBufferTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        DispatchQueue.global(qos: .userInitiated).sync {
            do {
                try handler.perform([self.visionRequest])
            } catch {
                print("Failed to perform Vision request: \(error)")
            }
        }

        currentBuffer = nil
        currentBufferTimestamp = nil
    }


    private func processObservations(for request: VNRequest, error: Error?) {
        if let results = request.results as? [VNRecognizedObjectObservation],
            let timestamp = currentBufferTimestamp {
            let personResults = results.filter { (observation) -> Bool in
                observation.labels.first?.identifier == "person"
            }

            if !recording && !personResults.isEmpty {
                recording = true
            }

            if !personResults.isEmpty, let pixelBuffer = currentBuffer {
                // Draw marker
                guard let processedPixelBuffer = objectMarkerDrawer.drawMarkers(for: personResults, onto: pixelBuffer)
                else { return }

                if !recorder.appendSampleBuffer(buffer: processedPixelBuffer, timestamp: timestamp) {
                    recorder.saveFile()
                    // Video duration has a 10 seconds limit
                    // Trigger another recording for this new detection
                    recorder = EventVideoRecorder()
                    recorder.delegate = self
                    recorder.appendSampleBuffer(buffer: processedPixelBuffer, timestamp: timestamp)
                }
            } else if recording, let buffer = currentBuffer {
                if !recorder.appendSampleBuffer(buffer: buffer, timestamp: timestamp) {
                    // Discard this buffer and stop recording due to 10 sec limit
                    recorder.saveFile()
                    // Trigger another recording for this new detection
                    recorder = EventVideoRecorder()
                    recorder.delegate = self
                    recording = false
                }
            }
        }
    }

}

extension ProcessVideoFileViewController: VideoFileCaptureDelegate {

    func videoFileCapture(_ capture: VideoFileCapture, didCaptureVideoFrame sampleBuffer: CMSampleBuffer) {
        predict(sampleBuffer: sampleBuffer)

        // Update progress bar
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let progress = Float(currentTime.value) / Float(videoFileCapture.duration.value)
        DispatchQueue.main.async {
            self.progressBar.progress = progress
        }
    }

    func videoFileCaptureFinished(_ capture: VideoFileCapture) {
        // Finalize last recording if there is one
        if recorder.hasData {
            recorder.saveFile()
            recording = false
        } else {
            displayExportFinishedUIIfNeeded()
        }
    }

    func videoFileCaptureFailed(_ capture: VideoFileCapture) {
        playButton.isEnabled = true
        detectButton.isEnabled = true
        progressBar.isHidden = true

        let ok = UIAlertAction(title: "OK", style: .default, handler: nil)
        let alert = UIAlertController(title: nil, message: "Failed to read source video", preferredStyle: .alert)
        alert.addAction(ok)
        present(alert, animated: true, completion: nil)
    }

    func displayExportFinishedUIIfNeeded() {
        guard !progressBar.isHidden else { return }

        playButton.isEnabled = true
        detectButton.isEnabled = true
        progressBar.isHidden = true

        let ok = UIAlertAction(title: "OK", style: .default, handler: nil)
        let alert = UIAlertController(title: nil, message: "Event videos have been saved into Photo Library", preferredStyle: .alert)
        alert.addAction(ok)
        present(alert, animated: true, completion: nil)
    }
}

extension ProcessVideoFileViewController: EventVideoRecorderDelegate {

    func eventVideoRecorderDidSavedVideo(_ recorder: EventVideoRecorder) {
        if videoFileCapture.finished {
            displayExportFinishedUIIfNeeded()
        }
    }

    func eventVideoRecorderNeedsLibraryPermission(_ recorder: EventVideoRecorder) {
        playButton.isEnabled = true
        detectButton.isEnabled = true
        progressBar.isHidden = true

        let ok = UIAlertAction(title: "OK", style: .default, handler: nil)
        let alert = UIAlertController(title: nil, message: "Please turn on permission for photo library", preferredStyle: .alert)
        alert.addAction(ok)
        present(alert, animated: true, completion: nil)
    }

    func eventVideoRecorderFailedToSavedVideo(_ recorder: EventVideoRecorder) {
        playButton.isEnabled = true
        detectButton.isEnabled = true
        progressBar.isHidden = true

        let ok = UIAlertAction(title: "OK", style: .default, handler: nil)
        let alert = UIAlertController(title: nil, message: "Fail to save video to library", preferredStyle: .alert)
        alert.addAction(ok)
        present(alert, animated: true, completion: nil)
    }


}
