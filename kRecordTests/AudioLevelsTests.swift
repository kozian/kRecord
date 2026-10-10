import Foundation
import Testing
@testable import kRecord

struct AudioLevelsTests {
    private func sine(amplitude: Float, frames: Int = 48_000, frequency: Float = 1_000) -> [Float] {
        (0..<frames).map { amplitude * sin(2 * .pi * frequency * Float($0) / 48_000) }
    }

    @Test func silenceMeasuresZero() {
        let samples = [Float](repeating: 0, count: 1024)
        let level = AudioLevel.measure(samples, frameCount: samples.count)
        #expect(level == .silence)
        #expect(level.meterValue() == 0)
    }

    @Test func fullScaleSine() {
        let samples = sine(amplitude: 1)
        let level = AudioLevel.measure(samples, frameCount: samples.count)
        #expect(abs(level.peak - 1) < 0.001)
        #expect(abs(level.rms - 1 / Float(2).squareRoot()) < 0.001)
        // RMS of a full-scale sine is -3 dBFS: 57/60 of the meter range.
        #expect(abs(level.meterValue() - 0.95) < 0.002)
    }

    @Test func quietSineMapsIntoMeterRange() {
        // -40 dBFS peak sine: RMS -43 dBFS -> (60 - 43) / 60.
        let samples = sine(amplitude: 0.01)
        let level = AudioLevel.measure(samples, frameCount: samples.count)
        #expect(abs(level.meterValue() - 17.0 / 60) < 0.005)
    }

    @Test func meterValueIsClamped() {
        #expect(AudioLevel.meterValue(amplitude: 0.0001) == 0)
        #expect(AudioLevel.meterValue(amplitude: 1) == 1)
        #expect(AudioLevel.meterValue(amplitude: 2) == 1)
    }

    @Test func measuresOneChannelOfInterleavedBuffer() {
        // Left channel full scale, right channel silent.
        let left = sine(amplitude: 1, frames: 4_800)
        var stereo = [Float](repeating: 0, count: left.count * 2)
        for (i, sample) in left.enumerated() { stereo[i * 2] = sample }

        let leftLevel = stereo.withUnsafeBufferPointer {
            AudioLevel.measure($0.baseAddress!, frameCount: left.count, stride: 2)
        }
        let rightLevel = stereo.withUnsafeBufferPointer {
            AudioLevel.measure($0.baseAddress! + 1, frameCount: left.count, stride: 2)
        }
        #expect(abs(leftLevel.peak - 1) < 0.001)
        #expect(rightLevel == .silence)
    }

    @Test func snapshotKeepsMaximumUntilTaken() {
        let snapshot = LevelSnapshot()
        snapshot.publish(AudioLevel(peak: 0.5, rms: 0.2), for: .microphone)
        snapshot.publish(AudioLevel(peak: 0.3, rms: 0.4), for: .microphone)
        snapshot.publish(AudioLevel(peak: 0.9, rms: 0.6), for: .system)

        let levels = snapshot.take()
        #expect(levels.microphone == AudioLevel(peak: 0.5, rms: 0.4))
        #expect(levels.system == AudioLevel(peak: 0.9, rms: 0.6))
        #expect(snapshot.take() == .silence)
    }
}
