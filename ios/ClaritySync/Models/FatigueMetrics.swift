//
//  FatigueMetrics.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/4/10.
//

import Foundation

struct FatigueMetrics: Equatable {
    var riskRaw: Float = 0              // 0..1, from current window
    var riskEMA: Float = 0              // 0..1, smoothed
    var noiseScore: Float = 0           // 0..1
    var perfScore: Float = 0            // 0..1
    var adjScore: Float = 0             // 0..1
    var adjEventsPerMin: Float = 0

    enum State: String, Equatable { 
        case normal, elevated, high
    }
    var state: State = .normal
    
    // Thresholds and state tracking (lowered for easier demo)
    private static let riskHighThreshold: Float = 0.50
    private static let riskElevatedThreshold: Float = 0.35
    private static let riskHighExitThreshold: Float = 0.35
    private static let riskElevatedExitThreshold: Float = 0.20
    
    mutating func updateState(riskEMA: Float) {
        self.riskEMA = riskEMA
        
        switch state {
        case .normal:
            if riskEMA >= Self.riskElevatedThreshold {
                state = .elevated
            }
        case .elevated:
            if riskEMA >= Self.riskHighThreshold {
                state = .high
            } else if riskEMA <= Self.riskElevatedExitThreshold {
                state = .normal
            }
        case .high:
            if riskEMA <= Self.riskHighExitThreshold {
                state = .elevated
            }
        }
    }
}
