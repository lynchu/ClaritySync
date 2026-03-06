import Foundation
import Accelerate

final class ConversationFeatureExtractor {

    // MARK: - Tunables (MVP)
    private let vadK: Float = 2.5                 // rms threshold = noiseFloor * vadK
    private let noiseEmaAlpha: Float = 0.02       // smaller = slower
    private let onsetThresholdDb: Float = 2.0     // envelope jump threshold in dB

    // MARK: - State
    private var sampleRate: Double = 48_000
    private var frameSize: Int = 960              // 20ms @ 48k
    private var frameSec: Double { Double(frameSize) / sampleRate }

    // noise floor in linear rms
    private var noiseFloorRms: Float = 1e-3

    // VAD + pause tracking
    private var inSpeech: Bool = false
    private var currentPauseSec: Double = 0

    // Window aggregation (30s)
    private var windowSec: Double = 30.0
    private var windowFrameCount: Int = 0
    private var silenceFrameCount: Int = 0
    private var pausesMs: [Float] = []            // store pause lengths in ms within window

    // Envelope for onset proxy
    private var lastEnvDb: Float = -120
    private var onsetCount: Int = 0

    // Behavior proxy
    private var adjustmentsCounterSnapshot: Int = 0
    private var adjustmentsInWindow: Int = 0

    // Cached metrics
    private var cached = ConversationMetrics.zero

    init(windowSec: Double = 30.0) {
        self.windowSec = windowSec
        pausesMs.reserveCapacity(512)
    }

    // Call from audio worker thread once per frame
    func update(frame: [Float], sampleRate sr: Double, frameSize fs: Int, adjustmentsCounter: Int) {
        if sr != sampleRate || fs != frameSize {
            // format changed -> reset window state conservatively
            sampleRate = sr
            frameSize = fs
            resetWindow()
        }

        // 1) RMS
        var rms: Float = 0
        vDSP_rmsqv(frame, 1, &rms, vDSP_Length(frame.count))
        rms = max(rms, 1e-8)

        // 2) Update noise floor (only when likely silence)
        // simple heuristic: if current rms is near noise floor, update; else keep
        let isNearNoise = rms < noiseFloorRms * 1.5
        if isNearNoise {
            noiseFloorRms = noiseEma(noiseFloorRms, rms, alpha: noiseEmaAlpha)
        }

        // 3) VAD
        let threshold = noiseFloorRms * vadK
        let speech = rms > threshold

        // 4) Pause tracking
        windowFrameCount += 1
        if speech {
            if !inSpeech {
                // transition: silence -> speech; record pause if meaningful
                if currentPauseSec >= 0.12 { // ignore tiny gaps
                    pausesMs.append(Float(currentPauseSec * 1000.0))
                }
                currentPauseSec = 0
            }
            inSpeech = true
        } else {
            silenceFrameCount += 1
            if inSpeech {
                // speech -> silence
                inSpeech = false
                currentPauseSec = frameSec
            } else {
                currentPauseSec += frameSec
            }
        }

        // 5) Speech-rate proxy via envelope onsets (dB jumps)
        let envDb = linToDb(rms)
        let d = envDb - lastEnvDb
        if d >= onsetThresholdDb {
            onsetCount += 1
        }
        lastEnvDb = envDb

        // 6) Adjustments/min proxy (count changes within window)
        if adjustmentsCounter != adjustmentsCounterSnapshot {
            adjustmentsInWindow += (adjustmentsCounter - adjustmentsCounterSnapshot)
            adjustmentsCounterSnapshot = adjustmentsCounter
        }

        // 7) If window full -> compute stats & reset
        let elapsed = Double(windowFrameCount) * frameSec
        if elapsed >= windowSec {
            cached = computeMetrics(latestSpeech: speech, latestRms: rms, windowElapsed: elapsed)
            resetWindow(keepCarryPause: true)
        } else {
            // Update cheap “instant” fields so UI can show live state even before window completes
            cached.isSpeech = speech
            cached.rmsDb = envDb
            cached.noiseFloorDb = linToDb(noiseFloorRms)
            cached.windowSec = windowSec
        }
    }

    func current() -> ConversationMetrics { cached }

    // MARK: - Helpers

    private func computeMetrics(latestSpeech: Bool, latestRms: Float, windowElapsed: Double) -> ConversationMetrics {
        var m = ConversationMetrics.zero
        m.isSpeech = latestSpeech
        m.rmsDb = linToDb(latestRms)
        m.noiseFloorDb = linToDb(noiseFloorRms)

        m.windowSec = windowElapsed
        m.silenceRatio = windowFrameCount > 0 ? Float(silenceFrameCount) / Float(windowFrameCount) : 0

        // pause stats
        if !pausesMs.isEmpty {
            let sorted = pausesMs.sorted()
            let mean = sorted.reduce(0, +) / Float(sorted.count)
            m.meanPauseMs = mean
            let idx = Int((0.95 * Float(sorted.count - 1)).rounded(.toNearestOrAwayFromZero))
            m.p95PauseMs = sorted[max(0, min(sorted.count - 1, idx))]
        }

        // onset rate
        m.onsetRatePerSec = windowElapsed > 0 ? Float(onsetCount) / Float(windowElapsed) : 0

        // adjustments/min
        m.adjustmentsPerMin = windowElapsed > 0 ? Float(adjustmentsInWindow) / Float(windowElapsed) * 60.0 : 0

        return m
    }

    private func resetWindow(keepCarryPause: Bool = false) {
        windowFrameCount = 0
        silenceFrameCount = 0
        pausesMs.removeAll(keepingCapacity: true)
        onsetCount = 0
        adjustmentsInWindow = 0
        // keep currentPauseSec if we are mid-silence across windows
        if !keepCarryPause {
            currentPauseSec = 0
            inSpeech = false
        }
    }

    private func noiseEma(_ prev: Float, _ x: Float, alpha: Float) -> Float {
        return (1 - alpha) * prev + alpha * x
    }

    private func linToDb(_ x: Float) -> Float {
        // 20*log10(x)
        return 20.0 * log10f(max(x, 1e-8))
    }
}

