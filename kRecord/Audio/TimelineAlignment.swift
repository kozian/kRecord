import CoreAudio
import Foundation
import Synchronization

/// Maps host time to the system audio frame timeline (design D6).
///
/// The aggregate IOProc calls `advance` once per cycle with the host time of the cycle's first
/// frame. Other threads read a consistent (frame, host time) pair through a sequence lock, so the
/// real-time writer never blocks.
final class TimelineAnchor: Sendable {
    struct Point: Equatable, Sendable {
        /// Index of a system audio frame since the start of the recording.
        var frame: Int
        var hostTime: UInt64
    }

    private let sequence = Atomic<UInt64>(0)
    private let frame = Atomic<Int>(0)
    private let hostTime = Atomic<UInt64>(0)
    private let framesWritten = Atomic<Int>(0)

    /// Real-time safe. Records that the next `frames` system frames start at `firstFrameHostTime`.
    func advance(frames: Int, firstFrameHostTime: UInt64) {
        let start = framesWritten.load(ordering: .relaxed)
        sequence.add(1, ordering: .acquiringAndReleasing)
        frame.store(start, ordering: .relaxed)
        hostTime.store(firstFrameHostTime, ordering: .relaxed)
        sequence.add(1, ordering: .acquiringAndReleasing)
        framesWritten.store(start + frames, ordering: .releasing)
    }

    /// The latest anchor, or `nil` before the first IO cycle.
    func latest() -> Point? {
        while true {
            let before = sequence.load(ordering: .acquiring)
            guard before != 0 else { return nil }
            if before % 2 == 1 { continue }
            let point = Point(frame: frame.load(ordering: .relaxed), hostTime: hostTime.load(ordering: .relaxed))
            if sequence.load(ordering: .acquiring) == before { return point }
        }
    }
}

/// Decides how microphone buffers from a separate engine join the system audio timeline.
enum MicAlignment {
    enum Action: Equatable {
        /// Write the buffer, after `silence` frames if the microphone fell behind.
        case write(silence: Int, dropLeading: Int)
        /// The whole buffer lies before the current microphone position (or before the timeline started).
        case drop
    }

    /// Jitter below this many frames is ignored so normal timing noise does not cut audio.
    static let toleranceFrames = 96

    /// - Parameters:
    ///   - bufferHostTime: host time of the buffer's first frame.
    ///   - frames: frames in the buffer.
    ///   - micFramesWritten: microphone frames written so far (including inserted silence).
    ///   - anchor: latest system timeline anchor.
    ///   - sampleRate: frames per second of both timelines.
    ///   - hostTicksPerSecond: host time units per second.
    static func action(bufferHostTime: UInt64, frames: Int, micFramesWritten: Int,
                       anchor: TimelineAnchor.Point, sampleRate: Double, hostTicksPerSecond: Double) -> Action {
        let deltaSeconds = (Double(bufferHostTime) - Double(anchor.hostTime)) / hostTicksPerSecond
        let position = anchor.frame + Int((deltaSeconds * sampleRate).rounded())
        guard position >= 0 else {
            let leading = -position
            return leading >= frames ? .drop : alignedWrite(position: 0, droppedLeading: leading, frames: frames,
                                                            micFramesWritten: micFramesWritten)
        }
        return alignedWrite(position: position, droppedLeading: 0, frames: frames, micFramesWritten: micFramesWritten)
    }

    private static func alignedWrite(position: Int, droppedLeading: Int, frames: Int, micFramesWritten: Int) -> Action {
        let difference = position - micFramesWritten
        if difference > toleranceFrames {
            return .write(silence: difference, dropLeading: droppedLeading)
        }
        if difference < -toleranceFrames {
            let overlap = -difference + droppedLeading
            return overlap >= frames ? .drop : .write(silence: 0, dropLeading: overlap)
        }
        return .write(silence: 0, dropLeading: droppedLeading)
    }

    static let hostTicksPerSecond: Double = {
        Double(AudioConvertNanosToHostTime(1_000_000_000))
    }()
}
