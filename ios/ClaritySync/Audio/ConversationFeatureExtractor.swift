import Foundation
import Accelerate

final class ConversationFeatureExtractor {

    // MARK: - Tunables (MVP)
    private let vadK: Float = 2.5
    private let noiseEmaAlpha: Float = 0.02
    private let onsetThresholdDb: Float = 2.0

    // NEW: silence moving average
    private let silenceMAUpdateSec: Double = 0.35     // 100 samples ≈ 35s
    private var silenceMATimer: Double = 0
    private var silenceDbMA = RollingMean(100)        // 100 values ≈ 30–40s
    private var silenceDbMAValue: Float = -120

    // MARK: - State
    private var sampleRate: Double = 48_000
    private var frameSize: Int = 960
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
    private var pausesMs: [Float] = []

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

    func update(frame: [Float], sampleRate sr: Double, frameSize fs: Int, adjustmentsCounter: Int) {
        if sr != sampleRate || fs != frameSize {
            sampleRate = sr
            frameSize = fs
            resetWindow()
            silenceMATimer = 0
            silenceDbMA.reset()
            silenceDbMAValue = -120
        }

        // 1) RMS
        var rms: Float = 0
        vDSP_rmsqv(frame, 1, &rms, vDSP_Length(frame.count))
        rms = max(rms, 1e-8)

        // Convert to dB for display / MA
        let envDb = linToDb(rms)

        // 2) Update noise floor (only when likely silence)
        let isNearNoise = rms < noiseFloorRms * 1.5
        if isNearNoise {
            noiseFloorRms = noiseEma(noiseFloorRms, rms, alpha: noiseEmaAlpha)
        }

        // NEW: silence moving average update every ~0.35s, only during silence
        silenceMATimer += frameSec

        // We'll compute speech using a dynamic noise baseline:
        // dynamicNoiseRms = max(EMA noiseFloor, silence MA baseline)
        let maRms = dbToLin(silenceDbMAValue)
        let dynamicNoiseRms = max(noiseFloorRms, maRms)

        // 3) VAD using dynamic baseline
        let threshold = dynamicNoiseRms * vadK
        let speech = rms > threshold

        if silenceMATimer >= silenceMAUpdateSec {
            silenceMATimer = 0
            if !speech {
                silenceDbMA.push(envDb)
                silenceDbMAValue = silenceDbMA.mean
            }
        }

        // 4) Pause tracking
        windowFrameCount += 1
        if speech {
            if !inSpeech {
                if currentPauseSec >= 0.12 {
                    pausesMs.append(Float(currentPauseSec * 1000.0))
                }
                currentPauseSec = 0
            }
            inSpeech = true
        } else {
            silenceFrameCount += 1
            if inSpeech {
                inSpeech = false
                currentPauseSec = frameSec
            } else {
                currentPauseSec += frameSec
            }
        }

        // 5) Speech-rate proxy via envelope onsets (dB jumps)
        let d = envDb - lastEnvDb
        if d >= onsetThresholdDb {
            onsetCount += 1
        }
        lastEnvDb = envDb

        // 6) Adjustments/min proxy
        if adjustmentsCounter != adjustmentsCounterSnapshot {
            adjustmentsInWindow += (adjustmentsCounter - adjustmentsCounterSnapshot)
            adjustmentsCounterSnapshot = adjustmentsCounter
        }

        // 7) Window full -> compute stats
        let elapsed = Double(windowFrameCount) * frameSec
        if elapsed >= windowSec {
            cached = computeMetrics(latestSpeech: speech, latestEnvDb: envDb, windowElapsed: elapsed)
            resetWindow(keepCarryPause: true)
        } else {
            // update instant fields
            cached.isSpeech = speech
            cached.rmsDb = envDb
            cached.noiseFloorDb = linToDb(noiseFloorRms)
            cached.silenceDbMA = silenceDbMAValue
            cached.windowSec = windowSec
        }
    }

    func current() -> ConversationMetrics { cached }
    
    /// Compute listening fatigue score from window metrics and adjustment events
    func computeFatigueScore(adjEventsPerMin: Float) -> FatigueMetrics {
        var fatigue = FatigueMetrics()
        
        // Thresholds from CSV analysis
        let noise_low: Float = -79.07
        let noise_high: Float = -78.32
        fatigue.noiseScore = normClamp(silenceDbMAValue, low: noise_low, high: noise_high)
        
        // Performance score: max of pause and silence
        let pause_low: Float = 540
        let pause_high: Float = 1540
        let pauseScore = normClamp(cached.p95PauseMs, low: pause_low, high: pause_high)
        
        let silence_low: Float = 0.21
        let silence_high: Float = 0.49
        let silenceScore = normClamp(cached.silenceRatio, low: silence_low, high: silence_high)
        
        fatigue.perfScore = max(pauseScore, silenceScore)
        
        // Adjustment score (normalized from debounced events)
        let adj_low: Float = 0
        let adj_high: Float = 6
        fatigue.adjScore = normClamp(adjEventsPerMin, low: adj_low, high: adj_high)
        fatigue.adjEventsPerMin = adjEventsPerMin
        
        // Risk formula: weighted sum
        fatigue.riskRaw = 0.35 * fatigue.noiseScore + 0.45 * fatigue.perfScore + 0.20 * fatigue.adjScore
        fatigue.riskRaw = max(0, min(1, fatigue.riskRaw))  // Clamp 0..1
        
        return fatigue
    }

    // MARK: - Helpers

    private func computeMetrics(latestSpeech: Bool, latestEnvDb: Float, windowElapsed: Double) -> ConversationMetrics {
        var m = ConversationMetrics.zero
        m.isSpeech = latestSpeech
        m.rmsDb = latestEnvDb
        m.noiseFloorDb = linToDb(noiseFloorRms)
        m.silenceDbMA = silenceDbMAValue

        m.windowSec = windowElapsed
        m.silenceRatio = windowFrameCount > 0 ? Float(silenceFrameCount) / Float(windowFrameCount) : 0

        if !pausesMs.isEmpty {
            let sorted = pausesMs.sorted()
            m.meanPauseMs = sorted.reduce(0, +) / Float(sorted.count)
            let idx = Int((0.95 * Float(sorted.count - 1)).rounded(.toNearestOrAwayFromZero))
            m.p95PauseMs = sorted[max(0, min(sorted.count - 1, idx))]
        }

        m.onsetRatePerSec = windowElapsed > 0 ? Float(onsetCount) / Float(windowElapsed) : 0
        m.adjustmentsPerMin = windowElapsed > 0 ? Float(adjustmentsInWindow) / Float(windowElapsed) * 60.0 : 0

        return m
    }

    private func resetWindow(keepCarryPause: Bool = false) {
        windowFrameCount = 0
        silenceFrameCount = 0
        pausesMs.removeAll(keepingCapacity: true)
        onsetCount = 0
        adjustmentsInWindow = 0
        if !keepCarryPause {
            currentPauseSec = 0
            inSpeech = false
        }
    }

    private func noiseEma(_ prev: Float, _ x: Float, alpha: Float) -> Float {
        (1 - alpha) * prev + alpha * x
    }

    private func linToDb(_ x: Float) -> Float {
        20.0 * log10f(max(x, 1e-8))
    }

    private func dbToLin(_ db: Float) -> Float {
        powf(10.0, db / 20.0)
    }
    
    private func normClamp(_ x: Float, low: Float, high: Float) -> Float {
        if high == low { return 0 }
        let clamped = max(low, min(high, x))
        return (clamped - low) / (high - low)
    }
}
