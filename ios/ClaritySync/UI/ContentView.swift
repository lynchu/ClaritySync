//
//  ContentView.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/2/10.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var audio = AudioController()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // Controls row
                    HStack(spacing: 12) {
                        Button(audio.isRunning ? "Stop" : "Start") {
                            audio.isRunning ? audio.stop() : audio.start()
                        }
                        .buttonStyle(.borderedProminent)

                        Spacer()

                        Text(audio.isRunning ? "Running" : "Ready")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                GroupBox("Demo Controls") {
                    VStack(alignment: .leading, spacing: 14) {
                        
                        Toggle("Enable DeepFilterNet", isOn: Binding(
                            get: { audio.params.dfnEnabled },
                            set: { v in
                                var p = audio.params
                                p.dfnEnabled = v
                                audio.applyParams(p)
                            }
                        ))

                        Toggle("Post-filter", isOn: Binding(
                            get: { audio.params.postFilterEnabled },
                            set: { v in
                                var p = audio.params
                                p.postFilterEnabled = v
                                audio.applyParams(p)
                            }
                        ))
                        .disabled(audio.params.dfnEnabled == false)
                        
                        VStack(alignment: .leading) {
                            Text(String(format: "Gain: %.2f", audio.params.gain))
                            Slider(value: Binding(
                                get: { Double(audio.params.gain) },
                                set: { v in
                                    var p = audio.params
                                    p.gain = Float(v)
                                    audio.applyParams(p)
                                }
                            ), in: 0.0...2.0)
                        }

                            VStack(alignment: .leading) {
                                Text(String(format: "Mix (processed): %.2f", audio.params.mix))
                                Slider(value: Binding(
                                    get: { Double(audio.params.mix) },
                                    set: { v in
                                        var p = audio.params
                                        p.mix = Float(v)
                                        audio.applyParams(p)
                                    }
                                ), in: 0.0...1.0)
                            }
                        }
                    }

                    MetricsView(
                        route: audio.routeInfo,
                        metrics: audio.metrics,
                        convo: audio.convo
                    )

                    Text("This demo only records from AirPods microphone (Bluetooth HFP).\nIf Start fails, reconnect AirPods and try again.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding()
            }
            .navigationTitle("ClaritySync Demo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("Mic: AirPods (HFP)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
