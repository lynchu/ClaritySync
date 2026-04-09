//
//  AdjustmentEventDetector.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/4/10.
//

import Foundation

final class AdjustmentEventDetector {
    private var lastParams: AudioParams = .demoDefault
    private var lastEventTimeSec: Double = 0
    private let cooldownMs: Float = 400.0
    
    // Rolling 60-second window of event timestamps
    private var eventTimestamps: [Double] = []
    private let rollingWindowSec: Double = 60.0
    
    // Events counted in the current fatigue window (for CSV logging)
    var eventsInWindow: Int = 0
    
    private let sampleRate: Double = 48_000
    
    func reset() {
        eventsInWindow = 0
    }
    
    /// Clear the rolling window and reset event tracking
    func clearRollingWindow() {
        eventTimestamps.removeAll()
        eventsInWindow = 0
        lastEventTimeSec = 0
    }
    
    /// Get the count of events in the rolling 60-second window (excludes old events)
    private func getEventsInRollingWindow(nowSec: Double) -> Int {
        // Remove events older than 60 seconds
        eventTimestamps.removeAll { nowSec - $0 > rollingWindowSec }
        return eventTimestamps.count
    }
    
    /// Calculate adjustments per minute based on rolling 60-second window.
    /// Returns immediate rate, not extrapolated.
    func getAdjustmentsPerMinute(nowSec: Double) -> Float {
        let count = getEventsInRollingWindow(nowSec: nowSec)
        if count == 0 { return 0 }
        
        // Count events in the last 60 seconds and extrapolate to per-minute
        // If we have 6 events in 60 seconds, that's 6 per minute
        return Float(count)
    }
    
    /// Check if this parameter change constitutes a countable adjustment event.
    /// - Parameters:
    ///   - newParams: New parameter values
    ///   - nowSec: Current time in seconds (use CACurrentMediaTime())
    /// - Returns: true if the event was counted, false otherwise
    func onParamsApplied(_ newParams: AudioParams, nowSec: Double) -> Bool {
        // Check cooldown
        let lastEventMs = lastEventTimeSec * 1000.0
        let nowMs = nowSec * 1000.0
        if nowMs - lastEventMs < Double(cooldownMs) {
            lastParams = newParams
            return false
        }
        
        // Check for meaningful changes
        let gainDelta = abs(newParams.gain - lastParams.gain)
        let mixDelta = abs(newParams.mix - lastParams.mix)
        let dfnToggled = newParams.dfnEnabled != lastParams.dfnEnabled
        
        let isMeaningfulChange = gainDelta >= 0.05 || mixDelta >= 0.03 || dfnToggled
        
        // Update state
        lastParams = newParams
        
        if isMeaningfulChange {
            lastEventTimeSec = nowSec
            eventTimestamps.append(nowSec)  // Add to rolling window
            eventsInWindow += 1              // For CSV logging
            return true
        }
        
        return false
    }
}
