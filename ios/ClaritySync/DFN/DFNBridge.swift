//
//  DFNMBridge.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/2/12.
//

import Foundation
import df3_ios

final class DFNBridge {
    private var h: DF3Handle?

    init?(modelDir: String, sampleRate: Int = 48_000, postFilterEnabled: Bool = true) {
        // df3_create return DF3Handle (void*)
        let handle = df3_create(modelDir, Int32(sampleRate))
        guard handle != nil else { return nil }
        self.h = handle
        df3_set_post_filter(handle, postFilterEnabled)
    }

    deinit {
        if let h { df3_destroy(h) }
    }

    func reset() {
        if let h { df3_reset(h) }
    }

    func setPostFilter(_ enabled: Bool) {
        if let h { df3_set_post_filter(h, enabled) }
    }

    /// Process mono Float32 hop (must be 480 samples)
    func processHop(input: UnsafePointer<Float>, output: UnsafeMutablePointer<Float>, hop: Int) -> Bool {
        guard let h else { return false }
        return df3_process(h, input, output, Int32(hop)) == 0
    }

    func latencySamples() -> Int {
        guard let h else { return 0 }
        return Int(df3_latency_samples(h))
    }
}
