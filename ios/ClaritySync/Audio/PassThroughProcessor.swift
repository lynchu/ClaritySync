//
//  PassThroughProcessor.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/2/10.
//

import AVFoundation

final class PassThroughProcessor: AudioProcessor {
    func process(buffer: AVAudioPCMBuffer, format: AVAudioFormat, params: AudioParams) -> AVAudioPCMBuffer {
        let frameLength = Int(buffer.frameLength)
        let channels = Int(format.channelCount)

        guard let inData = buffer.floatChannelData else { return buffer }

        let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameCapacity)!
        out.frameLength = buffer.frameLength

        guard let outData = out.floatChannelData else { return buffer }

        let g = params.gain
        let mix = params.mix
        let invMix = 1.0 - mix

        for ch in 0..<channels {
            let inCh = inData[ch]
            let outCh = outData[ch]
            for i in 0..<frameLength {
                let dry = inCh[i]
                let wet = dry * g
                outCh[i] = wet * mix + dry * invMix
            }
        }
        return out
    }
}
