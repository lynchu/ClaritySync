//
//  ema.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/2/10.
//

import Foundation

struct EMA {
    private let alpha: Double
    private(set) var value: Double = 0

    init(alpha: Double, initial: Double = 0) {
        self.alpha = alpha
        self.value = initial
    }

    mutating func update(_ x: Double) {
        value = value * (1.0 - alpha) + x * alpha
    }
}
