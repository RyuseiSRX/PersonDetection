//
//  EventVideoRecorder.swift
//  ObjectDetection
//
//  Created by Derek Tseng on 2020/10/13.
//  Copyright © 2020 MachineThink. All rights reserved.
//

import Foundation
import AVFoundation
import Photos

public protocol EventVideoRecorderDelegate: class {
    func eventVideoRecorderDidSavedVideo(_ recorder: EventVideoRecorder)
    func eventVideoRecorderNeedsLibraryPermission(_ recorder: EventVideoRecorder)
    func eventVideoRecorderFailedToSavedVideo(_ recorder: EventVideoRecorder)
}

public class EventVideoRecorder {

    private let writerInput: AVAssetWriterInput
    private let writer: AVAssetWriter
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let eventVideoTimeLimit: Float64 = 10

    private var startTime: CMTime?  // Not sure why duration of CMSampleBuffer is invalid, so use time calculation to get a rough value
    private(set) var hasData = false

    weak var delegate: EventVideoRecorderDelegate?

    init() {
        let settings: [String : Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: NSNumber(value: Float(1080)),
            AVVideoHeightKey: NSNumber(value: Float(1920))
        ]
        writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        writerInput.mediaTimeScale = CMTimeScale(600)

        let filePath = NSTemporaryDirectory() + "tempVideo_\(Date().timeIntervalSince1970).mp4"
        if FileManager.default.fileExists(atPath: filePath) {
            try! FileManager.default.removeItem(atPath: filePath)
        }
        writer = try! AVAssetWriter(url: URL(fileURLWithPath: filePath), fileType: .mp4)
        writer.add(writerInput)

        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: nil)
    }

    @discardableResult
    func appendSampleBuffer(buffer: CVPixelBuffer, timestamp: CMTime) -> Bool {
        if let startTime = startTime {
            let duration = CMTimeSubtract(timestamp, startTime)
            if CMTimeGetSeconds(duration) >= eventVideoTimeLimit {
                return false
            }
        } else {
            startTime = timestamp
            hasData =  true
            writer.startWriting()
            writer.startSession(atSourceTime: CMTime.zero)
        }

        let presentationTime = CMTime(seconds: timestamp.seconds - startTime!.seconds, preferredTimescale: writerInput.mediaTimeScale)
        while !writerInput.isReadyForMoreMediaData {
            let date = Date().addingTimeInterval(0.01)
            RunLoop.current.run(until: date)
        }
        return adaptor.append(buffer, withPresentationTime: presentationTime)
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
                            DispatchQueue.main.async {
                                self.delegate?.eventVideoRecorderFailedToSavedVideo(self)
                            }
                        } else {
                            print("Video has been exported to photo library.")
                            DispatchQueue.main.async {
                                self.delegate?.eventVideoRecorderDidSavedVideo(self)
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.delegate?.eventVideoRecorderNeedsLibraryPermission(self)
                    }
                }
            }
        }
    }
    
}
