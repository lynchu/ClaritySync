//
//  SpectralAnalyzer.swift
//  ClaritySync
//
//  Created by Lynn Chu on 2026/4/10.
//

import Foundation
import Accelerate

/// Computes spectral rolloff: the frequency below which 85% of the spectral energy is concentrated.
/// Accumulates rolloff points and returns the mean.
final class SpectralAnalyzer {
    private let sampleRate: Float
    private let fftSize: Int = 2048  // Smaller for faster updates
    private let hopSize: Int = 512   // 25% overlap
    
    // Rolling window of rolloff points
    private var rolloffPoints: [Float] = []
    private let maxRolloffPoints = 100
    
    // Accumulator for samples between FFT windows
    private var sampleBuffer: [Float] = []
    
    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        self.sampleBuffer.reserveCapacity(fftSize * 2)
    }
    
    /// Feed audio samples into the analyzer.
    func processSamples(_ samples: UnsafePointer<Float>, count: Int) -> Float? {
        // Accumulate samples
        for i in 0..<count {
            sampleBuffer.append(samples[i])
            
            // Process when we have enough samples
            if sampleBuffer.count >= fftSize {
                if let rolloff = computeRolloff(for: Array(sampleBuffer.prefix(fftSize))) {
                    rolloffPoints.append(rolloff)
                    
                    // Keep rolling window
                    if rolloffPoints.count > maxRolloffPoints {
                        rolloffPoints.removeFirst()
                    }
                }
                // Advance by hop size
                sampleBuffer.removeFirst(hopSize)
            }
        }
        
        // Return mean if we have accumulated points
        return rolloffPoints.isEmpty ? nil : rolloffPoints.mean()
    }
    
    /// Reset the analyzer state
    func reset() {
        sampleBuffer.removeAll(keepingCapacity: true)
        rolloffPoints.removeAll(keepingCapacity: true)
    }
    
    /// Get current mean spectral rolloff (non-consuming peek)
    func getMeanRolloff() -> Float? {
        return rolloffPoints.isEmpty ? nil : rolloffPoints.mean()
    }
    
    // MARK: - Private
    
    /// Compute spectral rolloff (frequency at 85% cumulative energy)
    private func computeRolloff(for window: [Float]) -> Float? {
        guard window.count == fftSize else { return nil }
        
        // Prepare windowed signal
        var windowed = window
        applyHannWindow(&windowed)
        
        // Compute magnitude spectrum
        guard let magnitude = computeFFT(&windowed) else { return nil }
        
        // Calculate cumulative energy
        let totalEnergy = magnitude.reduce(0, +)
        guard totalEnergy > 0 else { return nil }
        
        var cumulativeEnergy: Float = 0
        let energyThreshold = totalEnergy * 0.85  // 85% threshold
        
        // Find bin where cumulative energy crosses 85%
        var rolloffBin: Int = 1  // Start at 1 to avoid DC bin
        for (i, mag) in magnitude.enumerated() {
            cumulativeEnergy += mag
            if cumulativeEnergy >= energyThreshold {
                rolloffBin = max(1, i)  // Ensure at least bin 1
                break
            }
        }
        
        // Convert bin to frequency (Hz)
        let binFrequency = Float(rolloffBin) * sampleRate / Float(fftSize)
        
        // Sanity check: rolloff should be reasonable
        guard binFrequency > 0 && binFrequency <= sampleRate / 2.0 else { return nil }
        
        return binFrequency
    }
    
    /// Apply Hann window to signal (in-place)
    private func applyHannWindow(_ samples: inout [Float]) {
        let n = samples.count
        let pi2 = 2.0 * Float.pi
        
        for i in 0..<n {
            let w = 0.5 * (1.0 - cos(pi2 * Float(i) / Float(n - 1)))
            samples[i] *= w
        }
    }
    
    /// Compute magnitude spectrum using vDSP FFT
    private func computeFFT(_ signal: inout [Float]) -> [Float]? {
        guard signal.count == fftSize else { return nil }
        
        let log2N = vDSP_Length(log2f(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2N, Int32(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        // Prepare split complex
        var realPart = [Float](repeating: 0, count: fftSize)
        var imagPart = [Float](repeating: 0, count: fftSize)
        
        // Copy signal to real part
        signal.withUnsafeBufferPointer { buf in
            realPart.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress!.update(from: buf.baseAddress!, count: fftSize)
            }
        }
        
        var splitInput = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
        var splitOutput = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
        
        // Execute FFT
        vDSP_fft_zop(fftSetup, &splitInput, 1, &splitOutput, 1, log2N, Int32(kFFTDirection_Forward))
        
        // Compute magnitude (sqrt(real² + imag²)) for first half
        var magnitude = [Float](repeating: 0, count: fftSize / 2)
        vDSP_zvmags(&splitOutput, 1, &magnitude, 1, vDSP_Length(fftSize / 2))
        
        // Scale magnitude by window energy to compensate for Hann window attenuation
        let hannSum: Float = 0.375 * Float(fftSize)  // Hann window sum for normalization
        let scaleFactor = 2.0 / hannSum
        vDSP_vsmul(magnitude, 1, [scaleFactor], &magnitude, 1, vDSP_Length(magnitude.count))
        
        return magnitude
    }
}

// MARK: - Array Extension
extension Array where Element == Float {
    func mean() -> Float {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Float(count)
    }
}
