//
//  VolumeCalibrationSession.swift
//  ClaritySync
//

import Foundation
import AVFoundation

final class VolumeCalibrationSession {
    var onStep: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var timer: DispatchSourceTimer?

    private let sampleRate: Double = 48_000
    private let toneHz: Double = 880.0
    private let stepDurationSec: Double = 1.2
    // Expanded 50% from previous [-42, -10] span:
    // old span = 32 dB -> new span = 48 dB, centered at -26 dB => [-50, -2]
    private let minDbFS: Float = -50.0
    private let maxDbFS: Float = -2.0
    private let stepDbFS: Float = 3.0
    private(set) var currentStepDbFS: Float = -50.0

    func start() throws {
        try configureSessionWithFallbacks()

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = makeLoopingToneBuffer(format: format, seconds: 0.4)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()

        player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        player.play()
        currentStepDbFS = minDbFS
        updatePlayerVolume()
        onStep?(currentStepDbFS)
        startSweepTimer()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        player.stop()
        engine.stop()
        engine.reset()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func startSweepTimer() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + stepDurationSec, repeating: stepDurationSec)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            currentStepDbFS += stepDbFS
            if currentStepDbFS > maxDbFS {
                currentStepDbFS = minDbFS
            }
            updatePlayerVolume()
            onStep?(currentStepDbFS)
        }
        timer = t
        t.resume()
    }

    private func configureSessionWithFallbacks() throws {
        let session = AVAudioSession.sharedInstance()
        let attempts: [(AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)] = [
            (.playback, .default, [.allowBluetoothA2DP]),
            (.playback, .default, []),
            (.ambient, .default, [])
        ]

        var lastError: Error?
        for (category, mode, options) in attempts {
            do {
                try session.setCategory(category, mode: mode, options: options)
                // Route-dependent hints: keep as best effort.
                try? session.setPreferredSampleRate(sampleRate)
                try? session.setPreferredIOBufferDuration(0.01)
                try session.setActive(true, options: [])
                return
            } catch {
                lastError = error
                try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            }
        }

        throw lastError ?? NSError(domain: NSOSStatusErrorDomain, code: -50)
    }

    private func updatePlayerVolume() {
        player.volume = pow(10.0, currentStepDbFS / 20.0)
    }

    private func makeLoopingToneBuffer(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(seconds * sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buf.frameLength = frameCount

        guard let ch = buf.floatChannelData?[0] else { return buf }
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            // Warble tone to reduce listener fatigue during calibration.
            let sweep = sin(2.0 * .pi * 2.0 * t) * 40.0
            let freq = toneHz + sweep
            ch[i] = Float(sin(2.0 * .pi * freq * t))
        }
        return buf
    }
}
