//  DFModelMode.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/4/8.
//

import Foundation

enum DFModelMode: String, CaseIterable, Identifiable {
    case standard
    case lowLatency

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard:
            return "Standard"
        case .lowLatency:
            return "Low Latency"
        }
    }

    var resourceFolderName: String {
        switch self {
        case .standard:
            return "df3_standard"
        case .lowLatency:
            return "df3_ll"
        }
    }

    var shortDescription: String {
        switch self {
        case .standard:
            return "Current model with higher quality"
        case .lowLatency:
            return "Lower latency model"
        }
    }
}
