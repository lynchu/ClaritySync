//
//  AudioController_Legacy.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/2/10.
//
//  Note: kept only for reference/backward-compat builds.
//  Demo policy: ALWAYS use AirPods microphone (Bluetooth HFP). No routing toggle.
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class AudioControllerLegacy: ObservableObject {
    @Published private(set) var isRunning: Bool = false
    @Published var params: AudioParams = .demoDefault
    @Published private(set) var metrics: AudioMetrics = .init()
    @Published private(set) var routeInfo: AudioRouteInfo = .current()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let processor: AudioProcessor = PassThroughProcessor()
    private let routeMonitor = AudioRouteMonitor()

    private var ema = EMA(alpha: 0.05, initial: 0)
    private var internalDropCount: Int = 0

    // 20ms @ 48k
    private let tapBufferSize: AVAudioFrameCount = 960

    func start() {
        guard !isRunning else { return }
        do {
            try AudioSessionConfigurator.configureForAirPodsMicOnly(sampleRate: 48_000, ioBufferDuration: 0.02)
            try startEngine()

            routeMonitor.start { [weak self] in
                Task { @MainActor in self?.refreshRouteInfo() }
            }

            isRunning = true
            refreshRouteInfo()
        } catch {
            print("Audio start error: \(error)")
            isRunning = false
            refreshRouteInfo()
        }
    }

    func stop() {
        guard isRunning else { return }
        routeMonitor.stop()
        stopEngine()
        isRunning = false
        refreshRouteInfo()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func applyParams(_ newParams: AudioParams) {
        params = newParams
    }

    private func startEngine() throws {
        engine.attach(player)

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)

        engine.connect(player, to: engine.mainMixerNode, format: inputFormat)

        // Always enforce AirPods mic before tapping.
        try AudioSessionConfigurator.enforceAirPodsMic()

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: tapBufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let t0 = CACurrentMediaTime()
            let processed = self.processor.process(buffer: buffer, format: inputFormat, params: self.params)
            self.player.scheduleBuffer(processed, completionHandler: nil)
            let t1 = CACurrentMediaTime()

            let ms = (t1 - t0) * 1000.0
            let sr = inputFormat.sampleRate
            let bufMs = (Double(self.tapBufferSize) / sr) * 1000.0
            if ms > bufMs { self.internalDropCount += 1 }

            Task { @MainActor in
                self.ema.update(ms)
                self.metrics = AudioMetrics(emaProcMs: self.ema.value, dropCount: self.internalDropCount)
            }
        }

        try engine.start()
        player.play()
    }

    private func stopEngine() {
        engine.stop()
        engine.reset()
        player.stop()
        engine.inputNode.removeTap(onBus: 0)
        internalDropCount = 0
        ema = EMA(alpha: 0.05, initial: 0)
    }

    private func refreshRouteInfo() {
        routeInfo = AudioRouteInfo.current()
    }
}
