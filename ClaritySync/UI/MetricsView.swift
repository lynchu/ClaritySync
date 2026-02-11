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
        }
    }
}
