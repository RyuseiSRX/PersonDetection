//
//  EventVideoProducer.swift
//  ObjectDetection
//
//  Created by Derek Tseng on 2020/10/13.
//  Copyright © 2020 MachineThink. All rights reserved.
//

import Foundation
import AVFoundation

class EventVideoProducer {

    private let writerInput: AVAssetWriterInput

    init() {
        writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
    }

    func appendSampleBuffer(buffer: CMSampleBuffer) {
        writerInput.append(buffer)
    }

    func saveFile() {
    }
    
}
