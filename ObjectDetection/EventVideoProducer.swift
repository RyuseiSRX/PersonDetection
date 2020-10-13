//
//  EventVideoProducer.swift
//  ObjectDetection
//
//  Created by Derek Tseng on 2020/10/13.
//  Copyright © 2020 MachineThink. All rights reserved.
//

import Foundation
import AVFoundation
import Photos

class EventVideoProducer {

    private let writerInput: AVAssetWriterInput
    private let writer: AVAssetWriter
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor

    private var startTime: CMTime?  // Not sure why duration of CMSampleBuffer is invalid, so use time calculation to get a rough value
    private(set) var hasData = false

    init() {
        let settings: [String : Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: NSNumber(value: Float(1080)),
            AVVideoHeightKey: NSNumber(value: Float(1920))
        ]
        writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        writerInput.mediaTimeScale = CMTimeScale(bitPattern: 600)

        let filePath = NSTemporaryDirectory() + "tempVideo_\(Date().timeIntervalSince1970).mp4"
        if FileManager.default.fileExists(atPath: filePath) {
            try! FileManager.default.removeItem(atPath: filePath)
        }
        writer = try! AVAssetWriter(url: URL(fileURLWithPath: filePath), fileType: .mp4)
        writer.add(writerInput)

        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: nil)
    }

    @discardableResult
    func appendSampleBuffer(buffer: CMSampleBuffer) -> Bool {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer)
        if let startTime = startTime {
            let duration = CMTimeSubtract(timestamp, startTime)
            if CMTimeGetSeconds(duration) >= 10 {
                return false
            }
        } else {
            startTime = CMSampleBufferGetPresentationTimeStamp(buffer)
            hasData =  true
            writer.startWriting()
            writer.startSession(atSourceTime: CMTime.zero)
        }

        let presentationTime = CMTime(seconds: timestamp.seconds - startTime!.seconds, preferredTimescale: CMTimeScale(600))
        while !writerInput.isReadyForMoreMediaData {
            let date = Date().addingTimeInterval(0.01)
            RunLoop.current.run(until: date)
        }
        return adaptor.append(CMSampleBufferGetImageBuffer(buffer)!, withPresentationTime: presentationTime)
    }

    func saveFile() {
        startTime = nil

        writer.finishWriting {
            PHPhotoLibrary.requestAuthorization { (status) in
                if status == .authorized {
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.writer.outputURL)
                    }) { (success, error) in
                        if let error = error {
                            print("\(error.localizedDescription)")
                        } else {
                            print("Video has been exported to photo library.")
                        }
                    }
                } else {
                    // TODO: Tip for library permission
                }
            }
        }
    }
    
}
