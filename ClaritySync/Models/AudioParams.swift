//
//  AudioParams.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/2/10.
//

import Foundation

struct AudioParams: Equatable {
    /// 0..2 (1 = no change)
    var gain: Float = 1.0

    /// 0..1 (1 = fully processed, 0 = fully original)
    var mix: Float = 1.0

    static let demoDefault = AudioParams(gain: 1.0, mix: 1.0)
}
