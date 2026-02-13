//
//  DFNModelManager.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/2/12.
//

import Foundation

final class DFNModelManager {
    static let shared = DFNModelManager()
    private init() {}

    /// Returns bundle directory that contains enc.onnx / erb_dec.onnx / df_dec.onnx / config.ini
    func modelDirPath() throws -> String {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("df3_onnx", isDirectory: true) else {
            throw NSError(domain: "DFN", code: -1, userInfo: [NSLocalizedDescriptionKey: "Bundle resourceURL missing"])
        }

        let fm = FileManager.default
        let must = ["enc.onnx", "erb_dec.onnx", "df_dec.onnx", "config.ini"]
        for name in must {
            let p = url.appendingPathComponent(name).path
            if !fm.fileExists(atPath: p) {
                throw NSError(domain: "DFN", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing \(name) in df3_onnx/"])
            }
        }
        return url.path
    }
}
