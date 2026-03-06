//
//  RollingMean.swift
//  ClaritySync
//
//  Created by 張譯心 on 2026/3/6.
//

import Foundation

struct RollingMean {
    private var buf: [Float]
    private var sum: Float = 0
    private var idx: Int = 0
    private var filled: Int = 0

    init(_ n: Int) {
        buf = Array(repeating: 0, count: max(1, n))
    }

    mutating func reset() {
        sum = 0
        idx = 0
        filled = 0
        for i in buf.indices { buf[i] = 0 }
    }

    mutating func push(_ x: Float) {
        if filled < buf.count {
            filled += 1
        } else {
            sum -= buf[idx]
        }
        buf[idx] = x
        sum += x
        idx = (idx + 1) % buf.count
    }

    var mean: Float {
        filled == 0 ? 0 : sum / Float(filled)
    }

    var count: Int { filled }
    var capacity: Int { buf.count }
}
