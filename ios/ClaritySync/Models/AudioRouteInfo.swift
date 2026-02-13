//
//  AudioRouteInfo.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/2/10.
//

import AVFoundation

struct AudioRouteInfo: Equatable {
    var inputSummary: String
    var outputSummary: String

    nonisolated private static func pretty(_ p: AVAudioSessionPortDescription) -> String {
        "\(p.portName) (\(p.portType.rawValue))"
    }

    private static func preferred(_ ports: [AVAudioSessionPortDescription]) -> AVAudioSessionPortDescription? {
        // Prefer showing the Bluetooth device name when present.
        let btOrder: [AVAudioSession.Port] = [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP]
        for t in btOrder {
            if let p = ports.first(where: { $0.portType == t }) { return p }
        }
        return ports.first
    }

    static func current() -> AudioRouteInfo {
        let route = AVAudioSession.sharedInstance().currentRoute

        // Show a single, stable line for Input/Output.
        let inStr = preferred(route.inputs).map(pretty) ?? "-"
        let outStr = preferred(route.outputs).map(pretty) ?? "-"
        return .init(inputSummary: inStr, outputSummary: outStr)
    }
}
