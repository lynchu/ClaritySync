//
//  AudioSessionConfigurator.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/2/10.
//

import AVFoundation

enum AudioSessionConfigurator {

    enum SessionError: Error, LocalizedError {
        case airPodsMicNotFound

        var errorDescription: String? {
            switch self {
            case .airPodsMicNotFound:
                return "AirPods microphone (Bluetooth HFP) not found. Please connect AirPods and ensure they are selected for calls."
            }
        }
    }

    /// Demo policy: ONLY allow AirPods (Bluetooth HFP) as microphone input.
    /// - Note: Output is allowed to be A2DP for better quality when available.
    static func configureForAirPodsMicOnly(sampleRate: Double = 48_000,
                                           ioBufferDuration: TimeInterval = 0.02) throws {
        let s = AVAudioSession.sharedInstance()

        // Xcode 26+ prefers allowBluetoothHFP over allowBluetooth (deprecated).
        var opts: AVAudioSession.CategoryOptions = [.allowBluetoothHFP, .allowBluetoothA2DP]
        #if compiler(>=6.2)   // Xcode 26+
            opts.insert(.allowBluetoothHFP)
        #else
            opts.insert(.allowBluetooth)
        #endif

        try s.setCategory(.playAndRecord, mode: .voiceChat, options: opts)
        try s.setPreferredSampleRate(sampleRate)
        try s.setPreferredIOBufferDuration(ioBufferDuration)
        try s.setActive(true)

        try enforceAirPodsMic()
    }

    static func enforceAirPodsMic() throws {
        let s = AVAudioSession.sharedInstance()
        guard let inputs = s.availableInputs,
              let bt = inputs.first(where: { $0.portType == .bluetoothHFP }) else {
            throw SessionError.airPodsMicNotFound
        }

        // Clear any previous preference then enforce AirPods mic.
        try? s.setPreferredInput(nil)
        try s.setPreferredInput(bt)
    }
}
