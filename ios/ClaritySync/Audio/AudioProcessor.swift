//
//  AudioProcessor.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/2/10.
//

import AVFoundation

protocol AudioProcessor: AnyObject {
    func process(buffer: AVAudioPCMBuffer, format: AVAudioFormat, params: AudioParams) -> AVAudioPCMBuffer
}
