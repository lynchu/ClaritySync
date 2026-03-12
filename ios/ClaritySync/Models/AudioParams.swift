//
//  AudioParams.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/2/10.
//

import Foundation

struct AudioParams: Equatable {
    /// 0..5 (1 = no change)
    var gain: Float = 1.0


    /// 0..1 (1 = fully processed, 0 = fully original)
    var mix: Float = 1.0

    /// Enable DeepFilterNet processing
    var dfnEnabled: Bool = false

    /// Post-filter toggle (mask-based)
    var postFilterEnabled: Bool = true

    static let demoDefault = AudioParams(gain: 1.0, mix: 1.0, dfnEnabled: false, postFilterEnabled: true)
}
