//
//  MetricsView.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/2/10.
//

import SwiftUI

struct MetricsView: View {
    let route: AudioRouteInfo
    let metrics: AudioMetrics
    let convo: ConversationMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupBox("Audio Route") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Input: \(route.inputSummary)")
                        .font(.footnote)
                    Text("Output: \(route.outputSummary)")
                        .font(.footnote)
                }
            }

            GroupBox("Metrics") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "proc_ms (EMA): %.4f", metrics.emaProcMs))
                    Text("inFill: \(metrics.inFill)   outFill: \(metrics.outFill)")
                    Text("inDrops: \(metrics.dropCount)   outOverflows: \(metrics.outOverflows)")
                    Text("outUnderruns: \(metrics.outUnderruns)")
                }
                .font(.footnote)
            }
            
            GroupBox("Conversation Features") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("VAD: \(convo.isSpeech ? "Speech" : "Silence")")
                    Text(String(format: "RMS(dB): %.1f   Noise(dB): %.1f", convo.rmsDb, convo.noiseFloorDb))
                    Text(String(format: "silenceMA(dB, ~35s): %.1f", convo.silenceDbMA))
                    Text(String(format: "silenceRatio(%.0fs): %.2f", convo.windowSec, convo.silenceRatio))
                    Text(String(format: "pause mean/p95 (ms): %.0f / %.0f", convo.meanPauseMs, convo.p95PauseMs))
                    Text(String(format: "onsetRate (/s): %.2f", convo.onsetRatePerSec))
                    Text(String(format: "adjustments/min: %.2f", convo.adjustmentsPerMin))
                }
                .font(.footnote)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            
            GroupBox("Adaptive Gain Protection") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "Env Level: %.1f dB", metrics.envLevelDb))
                    Text(String(format: "Peak: %.1f dB", metrics.peakDb))
                    Text(String(format: "Env Gain: %.4f   Impulse Gain: %.4f", metrics.envGain, metrics.impulseGain))
                    Text(String(format: "Auto Gain: %.4f   Attenuation: %.2f dB", metrics.autoGain, metrics.autoAttenDb))
                    Text("Limiter: \(metrics.limiterActive ? "ACTIVE" : "idle")")
                        .foregroundColor(metrics.limiterActive ? .red : .secondary)
                }
                .font(.footnote)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            
            GroupBox("Listening Fatigue") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "Risk EMA: %.3f", metrics.fatigueRiskEMA))
                    Text("State: \(metrics.fatigueState.rawValue.capitalized)")
                        .foregroundColor(
                            metrics.fatigueState == .high ? .red :
                            metrics.fatigueState == .elevated ? .orange : .green
                        )
                }
                .font(.footnote)
            }
        }
    }
}
