//
//  VideoFileCapture.swift
//  ObjectDetection
//
//  Created by Derek Tseng on 2020/10/13.
//  Copyright © 2020 MachineThink. All rights reserved.
//

import AVFoundation
import Foundation

public protocol VideoFileCaptureDelegate: class {
    func videoFileCapture(_ capture: VideoFileCapture, didCaptureVideoFrame: CMSampleBuffer)
    func videoFileCaptureFinished(_ capture: VideoFileCapture)
    func videoFileCaptureFailed(_ capture: VideoFileCapture)
}

public class VideoFileCapture {

    let asset: AVAsset
    let assetReader: AVAssetReader
    private(set) var finished = false

    weak var delegate: VideoFileCaptureDelegate?
    var duration: CMTime {
        asset.duration
    }

    init(fileURL: URL) {
        asset = AVAsset(url: fileURL)
        assetReader = try! AVAssetReader(asset: asset)
    }

    func processFrames() {
        DispatchQueue.global().async {
            guard let videoTrack = self.asset.tracks(withMediaType: .video).first else {
                DispatchQueue.main.async {
                    self.delegate?.videoFileCaptureFailed(self)
                }
                return
            }

            let settings: [String : Any] = [
              kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)
            ]
            let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: settings)

            self.assetReader.add(readerOutput)
            let readingStarted = self.assetReader.startReading()
            print("Reading file started: \(readingStarted ? "YES" : "NO")")

            var sampleBuffer: CMSampleBuffer? = readerOutput.copyNextSampleBuffer()
            while sampleBuffer != nil {
                let buffer = sampleBuffer!
                self.delegate?.videoFileCapture(self, didCaptureVideoFrame: buffer)
                sampleBuffer = readerOutput.copyNextSampleBuffer()
            }
            self.finished = true
            DispatchQueue.main.async {
                self.delegate?.videoFileCaptureFinished(self)
            }
        }
    }

}
