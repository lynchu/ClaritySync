//
//  AudioController.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/2/10.
//

import Foundation
import AVFoundation
import Combine
import os.lock
import Accelerate

// MARK: - Thread-safe boxes

private final class ParamsBox {
    private var lock = os_unfair_lock_s()
    private var _value: AudioParams
    init(_ v: AudioParams) { _value = v }

    func set(_ v: AudioParams) {
        os_unfair_lock_lock(&lock)
        _value = v
        os_unfair_lock_unlock(&lock)
    }

    func get() -> AudioParams {
        os_unfair_lock_lock(&lock)
        let v = _value
        os_unfair_lock_unlock(&lock)
        return v
    }
}

private final class Counter {
    private var lock = os_unfair_lock_s()
    private var _v: Int = 0
    func reset() { os_unfair_lock_lock(&lock); _v = 0; os_unfair_lock_unlock(&lock) }
    func inc()   { os_unfair_lock_lock(&lock); _v += 1; os_unfair_lock_unlock(&lock) }
    func get() -> Int { os_unfair_lock_lock(&lock); let v = _v; os_unfair_lock_unlock(&lock); return v }
}


// MARK: - Ring buffer (tryLock on realtime threads)

private final class FloatRingBuffer {
    private var lock = os_unfair_lock_s()
    private let capacity: Int
    private var buf: [Float]
    private var writeIdx: Int = 0
    private var readIdx: Int = 0
    private var count: Int = 0

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.buf = Array(repeating: 0, count: self.capacity)
    }

    func clear() {
        os_unfair_lock_lock(&lock)
        writeIdx = 0; readIdx = 0; count = 0
        os_unfair_lock_unlock(&lock)
    }

    func availableToRead() -> Int {
        os_unfair_lock_lock(&lock)
        let c = count
        os_unfair_lock_unlock(&lock)
        return c
    }

    /// Try-write from realtime thread. Drops if can't lock or ring full.
    func tryWrite(_ input: UnsafePointer<Float>, count n: Int) -> Bool {
        guard n > 0 else { return true }
        if !os_unfair_lock_trylock(&lock) { return false }
        defer { os_unfair_lock_unlock(&lock) }

        if n > (capacity - count) { return false }

        var remaining = n
        var src = input
        while remaining > 0 {
            let chunk = min(remaining, capacity - writeIdx)
            buf.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress!.advanced(by: writeIdx).update(from: src, count: chunk)
            }
            writeIdx = (writeIdx + chunk) % capacity
            src = src.advanced(by: chunk)
            count += chunk
            remaining -= chunk
        }
        return true
    }

    /// Blocking read for worker thread.
    func readBlocking(_ output: UnsafeMutablePointer<Float>, count n: Int) -> Int {
        guard n > 0 else { return 0 }
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let toRead = min(n, count)
        if toRead == 0 { return 0 }

        var remaining = toRead
        var dst = output
        while remaining > 0 {
            let chunk = min(remaining, capacity - readIdx)
            buf.withUnsafeBufferPointer { src in
                dst.update(from: src.baseAddress!.advanced(by: readIdx), count: chunk)
            }
            readIdx = (readIdx + chunk) % capacity
            dst = dst.advanced(by: chunk)
            count -= chunk
            remaining -= chunk
        }
        return toRead
    }

    /// Try-read for realtime render thread.
    func tryRead(_ output: UnsafeMutablePointer<Float>, count n: Int) -> Int? {
        guard n > 0 else { return 0 }
        if !os_unfair_lock_trylock(&lock) { return nil }
        defer { os_unfair_lock_unlock(&lock) }

        let toRead = min(n, count)
        if toRead == 0 { return 0 }

        var remaining = toRead
        var dst = output
        while remaining > 0 {
            let chunk = min(remaining, capacity - readIdx)
            buf.withUnsafeBufferPointer { src in
                dst.update(from: src.baseAddress!.advanced(by: readIdx), count: chunk)
            }
            readIdx = (readIdx + chunk) % capacity
            dst = dst.advanced(by: chunk)
            count -= chunk
            remaining -= chunk
        }
        return toRead
    }
}

// MARK: - Processor

private protocol FrameProcessor: AnyObject {
    func process(input: UnsafePointer<Float>,
                 output: UnsafeMutablePointer<Float>,
                 frameCount: Int,
                 params: AudioParams)
}

/// Demo processor: gain + mix, frame-based
private final class GainMixProcessor: FrameProcessor {
    func process(input: UnsafePointer<Float>, output: UnsafeMutablePointer<Float>, frameCount: Int, params: AudioParams) {
        let g = params.gain
        let mix = params.mix
        let inv = (1.0 as Float) - mix
        let scale = g * mix + inv
        vDSP_vsmul(input, 1, [scale], output, 1, vDSP_Length(frameCount))
    }
}

// MARK: - AudioController (mic is ALWAYS AirPods HFP)

final class AudioController: ObservableObject {
    // UI-facing (only mutate on main)
    @Published private(set) var isRunning: Bool = false
    @Published var params: AudioParams = .demoDefault
    @Published private(set) var metrics: AudioMetrics = .init()
    @Published private(set) var routeInfo: AudioRouteInfo = .current()

    // Internal thread-safe state
    private let paramsBox = ParamsBox(.demoDefault)
    private let inDropCounter = Counter()
    private let outUnderrunCounter = Counter()
    private let outOverflowCounter = Counter()

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let routeMonitor = AudioRouteMonitor()

    private let processor: FrameProcessor = GainMixProcessor()

    private var inRing: FloatRingBuffer!
    private var outRing: FloatRingBuffer!

    private let workerQueue = DispatchQueue(label: "claritysync.audio.worker", qos: .userInitiated)
    private var workerRunning = false

    // Serialize start/stop
    private let switchQueue = DispatchQueue(label: "claritysync.audio.switch", qos: .userInitiated)

    // Config (will refresh from session/engine)
    private var sampleRate: Double = 48_000
    private var frameSize: Int = 960          // 20ms @ 48k
    private var ringSeconds: Double = 2.0

    // Worker metrics
    private var ema = EMA(alpha: 0.05, initial: 0)
    private var lastOutSample: Float = 0

    // Throttle UI metric publishing (avoid spamming main queue at audio rate)
    private var lastMetricsPublishT: Double = 0

    deinit { routeMonitor.stop() }

    // MARK: Public API

    func start() {
        guard !isRunning else { return }

        // Keep worker params in sync, reset metrics
        paramsBox.set(params)
        inDropCounter.reset()
        outUnderrunCounter.reset()
        outOverflowCounter.reset()
        ema = EMA(alpha: 0.05, initial: 0)
        lastOutSample = 0
        lastMetricsPublishT = 0

        switchQueue.async { [weak self] in
            guard let self else { return }
            do {
                // Enforce: AirPods mic only
                try AudioSessionConfigurator.configureForAirPodsMicOnly(sampleRate: 48_000, ioBufferDuration: 0.02)

                self.refreshHardwareFormatFromSession()
                self.setupRings()
                try self.setupEngineGraph()
                self.startWorker()
                try self.engine.start()

                self.routeMonitor.start { [weak self] in
                    guard let self else { return }
                    DispatchQueue.main.async { self.routeInfo = AudioRouteInfo.current() }
                }

                DispatchQueue.main.async {
                    self.metrics = AudioMetrics()
                    self.isRunning = true
                    self.routeInfo = AudioRouteInfo.current()
                }
            } catch {
                print("start error:", error)
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.routeInfo = AudioRouteInfo.current()
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }

        switchQueue.async { [weak self] in
            guard let self else { return }

            self.routeMonitor.stop()
            self.stopWorker()

            self.teardownEngineGraph()

            self.engine.stop()
            self.engine.reset()
            try? AVAudioSession.sharedInstance().setActive(false)

            DispatchQueue.main.async {
                self.isRunning = false
                self.routeInfo = AudioRouteInfo.current()
            }
        }
    }

    /// Called when sliders change; no restart
    func applyParams(_ p: AudioParams) {
        paramsBox.set(p)
        DispatchQueue.main.async { self.params = p }
    }

    // MARK: Session / Engine

    private func refreshHardwareFormatFromSession() {
        let s = AVAudioSession.sharedInstance()
        sampleRate = s.sampleRate
        frameSize = max(160, Int(sampleRate * 0.02))
    }

    private func setupRings() {
        let cap = Int(sampleRate * ringSeconds)
        inRing = FloatRingBuffer(capacity: cap)
        outRing = FloatRingBuffer(capacity: cap)
        inRing.clear()
        outRing.clear()
    }

    private func setupEngineGraph() throws {
        teardownEngineGraph()

        let input = engine.inputNode
        let hwInFormat = input.inputFormat(forBus: 0)
        sampleRate = hwInFormat.sampleRate
        frameSize = max(160, Int(sampleRate * 0.02))

        // Force a float32 mono tap format. This prevents floatChannelData == nil on some routes.
        guard let tapFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: sampleRate,
                                            channels: 1,
                                            interleaved: false) else {
            throw NSError(domain: "AudioController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create tap format"])
        }

        input.installTap(onBus: 0,
                         bufferSize: AVAudioFrameCount(frameSize),
                         format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let n = Int(buffer.frameLength)
            guard n > 0, let chData = buffer.floatChannelData else { return }

            let ok = self.inRing.tryWrite(chData[0], count: n)
            if !ok { self.inDropCounter.inc() }
        }

        // Source node (pull from outRing) as mono float32
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        let monoFormat = AVAudioFormat(streamDescription: &asbd)!

        let src = AVAudioSourceNode(format: monoFormat) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let n = Int(frameCount)

            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let mData = abl[0].mData else { return noErr }
            let outPtr = mData.bindMemory(to: Float.self, capacity: n)

            if let readN = self.outRing.tryRead(outPtr, count: n) {
                if readN < n {
                    let fill = self.lastOutSample
                    for i in readN..<n { outPtr[i] = fill }
                    self.outUnderrunCounter.inc()
                }
                self.lastOutSample = outPtr[max(0, n - 1)]
            } else {
                let fill = self.lastOutSample
                for i in 0..<n { outPtr[i] = fill }
                self.outUnderrunCounter.inc()
            }

            return noErr
        }

        sourceNode = src
        engine.attach(src)
        engine.connect(src, to: engine.mainMixerNode, format: monoFormat)
    }

    private func teardownEngineGraph() {
        engine.inputNode.removeTap(onBus: 0)
        if let src = sourceNode {
            engine.disconnectNodeOutput(src)
            engine.detach(src)
        }
        sourceNode = nil
    }

    // MARK: Worker

    private func startWorker() {
        guard !workerRunning else { return }
        workerRunning = true

        workerQueue.async { [weak self] in
            guard let self else { return }

            var inBuf = [Float](repeating: 0, count: self.frameSize)
            var outBuf = [Float](repeating: 0, count: self.frameSize)

            while self.workerRunning {
                if self.inRing.availableToRead() < self.frameSize {
                    Thread.sleep(forTimeInterval: 0.001)
                    continue
                }

                let got = inBuf.withUnsafeMutableBufferPointer { dst in
                    self.inRing.readBlocking(dst.baseAddress!, count: self.frameSize)
                }
                if got < self.frameSize {
                    Thread.sleep(forTimeInterval: 0.001)
                    continue
                }

                let t0 = CACurrentMediaTime()

                let p = self.paramsBox.get()
                inBuf.withUnsafeBufferPointer { inp in
                    outBuf.withUnsafeMutableBufferPointer { outp in
                        self.processor.process(input: inp.baseAddress!,
                                               output: outp.baseAddress!,
                                               frameCount: self.frameSize,
                                               params: p)
                    }
                }

                let wrote = outBuf.withUnsafeBufferPointer { ptr in
                    self.outRing.tryWrite(ptr.baseAddress!, count: self.frameSize)
                }
                if !wrote { self.outOverflowCounter.inc() }

                let t1 = CACurrentMediaTime()
                let ms = (t1 - t0) * 1000.0
                self.ema.update(ms)

                // Publish metrics at ~10Hz to make UI smooth and meaningful.
                let now = CACurrentMediaTime()
                if now - self.lastMetricsPublishT >= 0.1 {
                    self.lastMetricsPublishT = now

                    let m = AudioMetrics(
                        emaProcMs: self.ema.value,
                        dropCount: self.inDropCounter.get(),
                        inFill: self.inRing.availableToRead(),
                        outFill: self.outRing.availableToRead(),
                        outUnderruns: self.outUnderrunCounter.get(),
                        outOverflows: self.outOverflowCounter.get(),
                    )
                    DispatchQueue.main.async { self.metrics = m }
                }
            }
        }
    }

    private func stopWorker() {
        guard workerRunning else {
            inRing?.clear()
            outRing?.clear()
            return
        }

        workerRunning = false

        // Wait for the worker loop to exit cleanly before clearing rings.
        workerQueue.sync { }

        inRing?.clear()
        outRing?.clear()
    }
}
