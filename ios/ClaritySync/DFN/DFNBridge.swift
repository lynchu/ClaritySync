//
//  DFNBridge.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/2/12.
//

import Foundation
import df3_ios

final class DFNBridge {
    private var h: DF3Handle?
    private(set) var modelMode: DFModelMode

    init?(modelDir: String,
          modelMode: DFModelMode = .standard,
          sampleRate: Int = 48_000,
          postFilterEnabled: Bool = true) {

        let handle = df3_create(modelDir, Int32(sampleRate))
        guard handle != nil else { return nil }

        self.h = handle
        self.modelMode = modelMode
        df3_set_post_filter(handle, postFilterEnabled)
    }

    convenience init?(modelMode: DFModelMode,
                      sampleRate: Int = 48_000,
                      postFilterEnabled: Bool = true) {
        do {
            let dir = try DFModelLocator.modelDirPath(for: modelMode)
            self.init(modelDir: dir,
                      modelMode: modelMode,
                      sampleRate: sampleRate,
                      postFilterEnabled: postFilterEnabled)
        } catch {
            return nil
        }
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

    func processHop(input: UnsafePointer<Float>,
                    output: UnsafeMutablePointer<Float>,
                    hop: Int) -> Bool {
        guard let h else { return false }
        return df3_process(h, input, output, Int32(hop)) == 0
    }

    func latencySamples() -> Int {
        guard let h else { return 0 }
        return Int(df3_latency_samples(h))
    }
}
