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
                    Text(String(format: "silenceRatio(%.0fs): %.2f", convo.windowSec, convo.silenceRatio))
                    Text(String(format: "pause mean/p95 (ms): %.0f / %.0f", convo.meanPauseMs, convo.p95PauseMs))
                    Text(String(format: "onsetRate (/s): %.2f", convo.onsetRatePerSec))
                    Text(String(format: "adjustments/min: %.2f", convo.adjustmentsPerMin))
                }
                .font(.footnote)
            }
        }
    }
}
