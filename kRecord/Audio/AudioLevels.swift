import Foundation
import Synchronization

/// Peak and RMS of a block of samples, linear amplitude in 0...1 (full scale = 1).
struct AudioLevel: Equatable, Sendable {
    var peak: Float
    var rms: Float

    static let silence = AudioLevel(peak: 0, rms: 0)

    /// Measures `frameCount` frames of one channel in an interleaved buffer with `stride` samples per frame.
    /// Real-time safe.
    static func measure(_ samples: UnsafePointer<Float>, frameCount: Int, stride: Int = 1) -> AudioLevel {
        guard frameCount > 0 else { return .silence }
        var peak: Float = 0
        var sumOfSquares: Float = 0
        for frame in 0..<frameCount {
            let sample = samples[frame * stride]
            peak = max(peak, abs(sample))
            sumOfSquares += sample * sample
        }
        return AudioLevel(peak: min(peak, 1), rms: min((sumOfSquares / Float(frameCount)).squareRoot(), 1))
    }

    /// Meter position in 0...1: RMS mapped linearly in decibels from `floorDecibels` (0) to 0 dBFS (1).
    func meterValue(floorDecibels: Float = -60) -> Float {
        Self.meterValue(amplitude: rms, floorDecibels: floorDecibels)
    }

    static func meterValue(amplitude: Float, floorDecibels: Float = -60) -> Float {
        guard amplitude > 0 else { return 0 }
        let decibels = 20 * log10(amplitude)
        return min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
    }
}

/// Microphone and system audio levels shared between the real-time thread and the UI (design D4).
///
/// The IO thread calls `publish` for every block; the main actor polls `take` at about 20 Hz.
/// `take` returns the highest peak and RMS published since the previous `take`, so short
/// transients between polls still move the meters, then resets them.
final class LevelSnapshot: Sendable {
    struct Levels: Equatable, Sendable {
        var microphone: AudioLevel
        var system: AudioLevel

        static let silence = Levels(microphone: .silence, system: .silence)
    }

    enum Source: Sendable {
        case microphone
        case system
    }

    // Float bit patterns; Float itself is not atomic-representable.
    private let microphonePeak = Atomic<UInt32>(0)
    private let microphoneRMS = Atomic<UInt32>(0)
    private let systemPeak = Atomic<UInt32>(0)
    private let systemRMS = Atomic<UInt32>(0)

    /// Real-time safe.
    func publish(_ level: AudioLevel, for source: Source) {
        switch source {
        case .microphone:
            Self.raise(microphonePeak, to: level.peak)
            Self.raise(microphoneRMS, to: level.rms)
        case .system:
            Self.raise(systemPeak, to: level.peak)
            Self.raise(systemRMS, to: level.rms)
        }
    }

    func take() -> Levels {
        Levels(
            microphone: AudioLevel(peak: Self.drain(microphonePeak), rms: Self.drain(microphoneRMS)),
            system: AudioLevel(peak: Self.drain(systemPeak), rms: Self.drain(systemRMS))
        )
    }

    private static func raise(_ atomic: borrowing Atomic<UInt32>, to value: Float) {
        // Non-negative floats order the same as their bit patterns.
        let bits = max(value, 0).bitPattern
        var current = atomic.load(ordering: .relaxed)
        while bits > current {
            let (exchanged, original) = atomic.compareExchange(
                expected: current, desired: bits, ordering: .relaxed)
            if exchanged { return }
            current = original
        }
    }

    private static func drain(_ atomic: borrowing Atomic<UInt32>) -> Float {
        Float(bitPattern: atomic.exchange(0, ordering: .relaxed))
    }
}
