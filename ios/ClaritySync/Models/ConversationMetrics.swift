import Foundation

struct ConversationMetrics: Equatable {
    // Instant / short-horizon
    var isSpeech: Bool = false
    var rmsDb: Float = -120.0
    var noiseFloorDb: Float = -120.0
    
    // moving average of silence level (dB), ~30–40s horizon
    var silenceDbMA: Float = -120.0

    // Window stats (default: last 30s)
    var windowSec: Double = 30.0
    var silenceRatio: Float = 0.0          // 0..1
    var meanPauseMs: Float = 0.0
    var p95PauseMs: Float = 0.0
    var onsetRatePerSec: Float = 0.0       // speech-rate proxy

    // Behavior proxy
    var adjustmentsPerMin: Float = 0.0

    static let zero = ConversationMetrics()
}
