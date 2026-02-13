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

    init(emaProcMs: Double = 0,
         dropCount: Int = 0,
         inFill: Int = 0,
         outFill: Int = 0,
         outUnderruns: Int = 0,
         outOverflows: Int = 0) {
        self.emaProcMs = emaProcMs
        self.dropCount = dropCount
        self.inFill = inFill
        self.outFill = outFill
        self.outUnderruns = outUnderruns
        self.outOverflows = outOverflows
    }
}
