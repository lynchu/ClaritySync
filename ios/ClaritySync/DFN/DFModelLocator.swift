//
//  DFModelLocator.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/4/8.
//

import Foundation

enum DFModelLocatorError: Error, LocalizedError {
    case resourceFolderNotFound(String)
    case modelFileMissing(String)

    var errorDescription: String? {
        switch self {
        case .resourceFolderNotFound(let path):
            return "DFN resource folder not found: \(path)"
        case .modelFileMissing(let path):
            return "DFN resource file missing: \(path)"
        }
    }
}

enum DFModelLocator {
    static func modelDirPath(for mode: DFModelMode) throws -> String {
        guard let resourceURL = Bundle.main.resourceURL else {
            throw DFModelLocatorError.resourceFolderNotFound(mode.resourceFolderName)
        }

        let folderURL = resourceURL.appendingPathComponent(mode.resourceFolderName, isDirectory: true)
        let fm = FileManager.default

        guard fm.fileExists(atPath: folderURL.path) else {
            throw DFModelLocatorError.resourceFolderNotFound(folderURL.path)
        }

        let requiredFiles = [
            folderURL.appendingPathComponent("enc.onnx").path,
            folderURL.appendingPathComponent("erb_dec.onnx").path,
            folderURL.appendingPathComponent("df_dec.onnx").path,
            folderURL.appendingPathComponent("config.ini").path
        ]

        for path in requiredFiles {
            guard fm.fileExists(atPath: path) else {
                throw DFModelLocatorError.modelFileMissing(path)
            }
        }

        return folderURL.path
    }
}
