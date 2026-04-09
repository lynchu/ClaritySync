//
//  AudioMetrics.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/2/10.
//

import Foundation

struct AudioMetrics: Equatable {
    var emaProcMs: Double
    var dropCount: Int

    // Optional (nice to have for “real-time feel”)
    var inFill: Int
    var outFill: Int
    var outUnderruns: Int
    var outOverflows: Int
    
    // Adaptive gain protection
    var envLevelDb: Float = -120.0          // Sustained controller level
    var peakDb: Float = -120.0              // Peak level this frame
    var envGain: Float = 1.0                // Sustained controller output
    var impulseGain: Float = 1.0            // Impulse limiter output
    var autoGain: Float = 1.0               // Combined: min(envGain, impulseGain)
    var autoAttenDb: Float = 0.0            // Attenuation in dB
    var limiterActive: Bool = false         // Is hold active
    
    // Listening fatigue metrics
    var fatigueRiskRaw: Float = 0.0
    var fatigueRiskEMA: Float = 0.0
    var fatigueState: FatigueMetrics.State = .normal

    init(emaProcMs: Double = 0,
         dropCount: Int = 0,
         inFill: Int = 0,
         outFill: Int = 0,
         outUnderruns: Int = 0,
         outOverflows: Int = 0,
         envLevelDb: Float = -120.0,
         peakDb: Float = -120.0,
         envGain: Float = 1.0,
         impulseGain: Float = 1.0,
         autoGain: Float = 1.0,
         autoAttenDb: Float = 0.0,
         limiterActive: Bool = false,
         fatigueRiskRaw: Float = 0.0,
         fatigueRiskEMA: Float = 0.0,
         fatigueState: FatigueMetrics.State = .normal) {
        self.emaProcMs = emaProcMs
        self.dropCount = dropCount
        self.inFill = inFill
        self.outFill = outFill
        self.outUnderruns = outUnderruns
        self.outOverflows = outOverflows
        self.envLevelDb = envLevelDb
        self.peakDb = peakDb
        self.envGain = envGain
        self.impulseGain = impulseGain
        self.autoGain = autoGain
        self.autoAttenDb = autoAttenDb
        self.limiterActive = limiterActive
        self.fatigueRiskRaw = fatigueRiskRaw
        self.fatigueRiskEMA = fatigueRiskEMA
        self.fatigueState = fatigueState
    }
}
