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

                    // MARK: - Transport
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

                    // MARK: - DeepFilterNet Model
                    GroupBox("DeepFilterNet Model") {
                        VStack(alignment: .leading, spacing: 14) {

                            Picker("Model", selection: Binding(
                                get: { audio.dfnModelMode },
                                set: { audio.setDFNModelMode($0) }
                            )) {
                                ForEach(DFModelMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(audio.dfnModelMode.shortDescription)
                                .font(.footnote)
                                .foregroundColor(.secondary)

                            HStack {
                                Text("Model latency")
                                    .font(.footnote)
                                Spacer()
                                Text("\(audio.dfnModelLatencySamples) samples / \(audio.dfnModelLatencyMs, specifier: "%.2f") ms")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // MARK: - Demo Controls
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
                            .disabled(!audio.params.dfnEnabled)
                            
                            Toggle("Auto Protection Enabled", isOn: Binding(
                                get: { audio.params.autoGainEnabled },
                                set: { v in
                                    var p = audio.params
                                    p.autoGainEnabled = v
                                    audio.applyParams(p)
                                }
                            ))

                            VStack(alignment: .leading) {
                                Text(String(format: "Gain: %.2f", audio.params.gain))
                                Slider(value: Binding(
                                    get: { Double(audio.params.gain) },
                                    set: { v in
                                        var p = audio.params
                                        p.gain = Float(v)
                                        audio.applyParams(p)
                                    }
                                ), in: 0.0...5.0)
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

                    // MARK: - Logging
                    GroupBox("Logging (CSV)") {
                        VStack(alignment: .leading, spacing: 12) {

                            HStack {
                                Text("Record every: \(audio.recordEverySec, specifier: "%.2f") s")
                                    .font(.footnote)
                                Spacer()
                            }

                            Slider(value: $audio.recordEverySec, in: 0.1...5.0, step: 0.1)
                                .disabled(audio.isRecording)

                            HStack(spacing: 12) {
                                Button(audio.isRecording ? "Stop Recording" : "Start Recording") {
                                    audio.isRecording ? audio.stopRecording() : audio.startRecording()
                                }
                                .buttonStyle(.bordered)

                                if audio.isRecording {
                                    Text("Recording…")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                } else if !audio.recordedFiles.isEmpty {
                                    Text("Files ready: \(audio.recordedFiles.count)")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }

                            if !audio.recordedFiles.isEmpty {
                                Divider()

                                Text("Export files:")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)

                                ForEach(audio.recordedFiles, id: \.self) { url in
                                    ShareLink(item: url) {
                                        Text(url.lastPathComponent)
                                            .font(.footnote)
                                    }
                                }

                                Text("Tip: Use AirDrop / Files to move CSV to your Mac for plotting.")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    // MARK: - Metrics
                    MetricsView(
                        route: audio.routeInfo,
                        metrics: audio.metrics,
                        convo: audio.convo
                    )

                    Spacer(minLength: 8)

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
