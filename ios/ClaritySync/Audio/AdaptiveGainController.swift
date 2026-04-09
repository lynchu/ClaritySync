//
//  AdaptiveGainController.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/4/10.
//

import Foundation
import Accelerate

/// Adaptive gain protection controller: sustain + impulse layers
final class AdaptiveGainController {
    
    // MARK: - Sustained Environment Control
    private struct SustainedControl {
        // Thresholds & shape
        var thresholdDb: Float = -30.0      // Threshold
        var kneeDb: Float = 6.0             // Knee width for soft corner
        var ratio: Float = 3.0              // Compression ratio above threshold
        var maxReductionDb: Float = 12.0    // Cap reduction
        var hysteresisDb: Float = 3.0       // Release gate threshold
        
        // Time constants
        var attackTauSec: Float = 0.3
        var releaseTauSec: Float = 2.0
        
        // State
        var envLevelDb: Float = -120.0      // Smoothed input level
        var envGain: Float = 1.0            // Output gain (0..1)
        var inSuppressionMode: Bool = false // For hysteresis
        
        mutating func update(inputRmsDb: Float, frameSec: Float) {
            // Asymmetric EMA
            let alpha: Float
            if inputRmsDb > envLevelDb {
                // Attack: faster rise
                alpha = 1.0 - exp(-frameSec / attackTauSec)
            } else {
                // Release: slower fall
                alpha = 1.0 - exp(-frameSec / releaseTauSec)
            }
            
            envLevelDb = envLevelDb * (1.0 - alpha) + inputRmsDb * alpha
            
            // Soft knee compression
            let kneeStart = thresholdDb
            let kneeEnd = thresholdDb + kneeDb
            
            let reductionDb: Float
            if envLevelDb <= kneeStart {
                // Below threshold: no reduction
                reductionDb = 0.0
                inSuppressionMode = false
            } else if envLevelDb >= kneeEnd {
                // Above knee: full ratio
                let excessDb = envLevelDb - kneeEnd
                reductionDb = min((excessDb / ratio) + (kneeDb / 2.0), maxReductionDb)
                inSuppressionMode = true
            } else {
                // In knee: soft ramp
                let kneePos = (envLevelDb - kneeStart) / kneeDb  // 0..1
                let excessDb = envLevelDb - thresholdDb
                let fullReduction = min((excessDb / ratio), maxReductionDb)
                // Quadratic ease-in
                reductionDb = fullReduction * (kneePos * kneePos)
                inSuppressionMode = (envLevelDb > thresholdDb)
            }
            
            // Hysteresis: don't release until well below threshold
            if inSuppressionMode && envLevelDb < (thresholdDb - hysteresisDb) {
                inSuppressionMode = false
            }
            
            // Convert reduction to gain
            envGain = pow(10.0, -reductionDb / 20.0)
        }
    }
    
    // MARK: - Impulse Limiter
    private struct ImpulseLimiter {
        // Thresholds
        var thresholdDb: Float = -6.0       // Peak threshold
        var safetyMarginDb: Float = 1.0     // Extra margin
        var maxReductionDb: Float = 18.0    // Cap reduction
        
        // Time constants
        var holdSec: Float = 0.15
        var releaseTauSec: Float = 0.5
        
        // State
        var impulseGain: Float = 1.0
        var holdRemainingFrames: Int = 0    // Frame count
        
        mutating func update(peakDb: Float, frameSec: Float, frameSize: Int) {
            let frameCount = 1  // Process per frame
            
            // Decrement hold timer
            if holdRemainingFrames > 0 {
                holdRemainingFrames -= 1
            }
            
            if peakDb <= thresholdDb {
                // Below threshold: smooth return to 1.0
                let alpha = 1.0 - exp(-frameSec / releaseTauSec)
                impulseGain = impulseGain * (1.0 - alpha) + 1.0 * alpha
            } else {
                // Above threshold: clamp peak
                let excessDb = peakDb - thresholdDb + safetyMarginDb
                let neededReductionDb = min(excessDb, maxReductionDb)
                let gNeeded = pow(10.0, -neededReductionDb / 20.0)
                
                // Never increase during attack
                impulseGain = min(impulseGain, gNeeded)
                
                // Start hold timer
                holdRemainingFrames = max(1, Int(Float(frameSize) * holdSec / 48000.0))
            }
            
            // During hold, don't release
            if holdRemainingFrames > 0 && impulseGain < 1.0 {
                // Keep it suppressed during hold
            } else if holdRemainingFrames == 0 && peakDb <= thresholdDb {
                // After hold and peak is down, start smooth release
                let alpha = 1.0 - exp(-frameSec / releaseTauSec)
                impulseGain = impulseGain * (1.0 - alpha) + 1.0 * alpha
            }
        }
    }
    
    // MARK: - Public Interface
    
    private var sustained = SustainedControl()
    private var limiter = ImpulseLimiter()
    private var sampleRate: Double = 48_000
    private var frameSize: Int = 960
    private var frameSec: Float = 0.02
    
    // Published state for UI/logging
    var envLevelDb: Float { sustained.envLevelDb }
    var peakDb: Float = -120.0
    var autoGain: Float = 1.0
    var autoAttenDb: Float { -20.0 * log10(autoGain) }
    var limiterActive: Bool { limiter.holdRemainingFrames > 0 }
    
    // Individual gains for logging
    var envGain: Float { sustained.envGain }
    var impulseGain: Float { limiter.impulseGain }
    
    init(sampleRate: Double = 48_000, frameSize: Int = 960) {
        self.sampleRate = sampleRate
        self.frameSize = frameSize
        self.frameSec = Float(frameSize) / Float(sampleRate)
    }
    
    /// Update with input frame and compute adaptive gain
    /// - Parameter inBuf: Input audio buffer
    /// - Parameter rmsDb: RMS level in dB (from feature extractor)
    /// - Parameter enabled: Whether adaptive protection is enabled
    /// - Returns: Effective gain multiplier (0..1)
    func process(inBuf: [Float], rmsDb: Float, enabled: Bool) -> Float {
        guard enabled else {
            // Reset to identity when disabled
            sustained.envGain = 1.0
            limiter.impulseGain = 1.0
            autoGain = 1.0
            return 1.0
        }
        
        // Compute peak
        var peak: Float = 0.0
        vDSP_maxv(inBuf, 1, &peak, vDSP_Length(inBuf.count))
        peak = abs(peak)  // Handle negative peaks
        peakDb = 20.0 * log10(max(peak, 1e-8))
        
        // Update sustained controller
        sustained.update(inputRmsDb: rmsDb, frameSec: frameSec)
        
        // Update impulse limiter
        limiter.update(peakDb: peakDb, frameSec: frameSec, frameSize: frameSize)
        
        // Combine conservatively: use minimum
        autoGain = min(sustained.envGain, limiter.impulseGain)
        
        return autoGain
    }
    
    /// Reset internal state (on stop/restart)
    func reset() {
        sustained.envLevelDb = -120.0
        sustained.envGain = 1.0
        sustained.inSuppressionMode = false
        limiter.impulseGain = 1.0
        limiter.holdRemainingFrames = 0
        peakDb = -120.0
        autoGain = 1.0
    }
}
