import Foundation
import Testing
@testable import kRecord

struct TimelineAlignmentTests {
    // 1 tick = 1 µs keeps the arithmetic readable: 48 kHz -> 1 frame every 20.83 ticks.
    private let ticks = 1_000_000.0
    private let rate = 48_000.0

    private func action(at hostTime: UInt64, frames: Int = 480, written: Int,
                        anchor: TimelineAnchor.Point = .init(frame: 48_000, hostTime: 10_000_000)) -> MicAlignment.Action {
        MicAlignment.action(bufferHostTime: hostTime, frames: frames, micFramesWritten: written,
                            anchor: anchor, sampleRate: rate, hostTicksPerSecond: ticks)
    }

    @Test func bufferOnScheduleIsWritten() {
        // Anchor: frame 48 000 at t = 10 s. A buffer at t = 10.5 s belongs at frame 72 000.
        #expect(action(at: 10_500_000, written: 72_000) == .write(silence: 0, dropLeading: 0))
    }

    @Test func smallJitterIsIgnored() {
        #expect(action(at: 10_500_000, written: 72_000 - MicAlignment.toleranceFrames) == .write(silence: 0, dropLeading: 0))
        #expect(action(at: 10_500_000, written: 72_000 + MicAlignment.toleranceFrames) == .write(silence: 0, dropLeading: 0))
    }

    @Test func lateMicrophoneIsPaddedWithSilence() {
        // The microphone has only 71 000 frames, but this buffer belongs at 72 000.
        #expect(action(at: 10_500_000, written: 71_000) == .write(silence: 1_000, dropLeading: 0))
    }

    @Test func overlappingFramesAreDropped() {
        // 200 frames of this buffer were already covered (written up to 72 200).
        #expect(action(at: 10_500_000, written: 72_200) == .write(silence: 0, dropLeading: 200))
        // A buffer entirely in the past is dropped.
        #expect(action(at: 10_500_000, frames: 480, written: 73_000) == .drop)
    }

    @Test func buffersBeforeTimelineStartAreDropped() {
        let start = TimelineAnchor.Point(frame: 0, hostTime: 10_000_000)
        // 100 ms before the first system frame.
        #expect(action(at: 9_900_000, frames: 480, written: 0, anchor: start) == .drop)
        // Straddling the start: the first 240 frames (5 ms) are before it.
        #expect(action(at: 9_995_000, frames: 480, written: 0, anchor: start) == .write(silence: 0, dropLeading: 240))
    }

    @Test func anchorPublishesConsistentPoints() {
        let anchor = TimelineAnchor()
        #expect(anchor.latest() == nil)
        anchor.advance(frames: 512, firstFrameHostTime: 1_000)
        #expect(anchor.latest() == .init(frame: 0, hostTime: 1_000))
        anchor.advance(frames: 512, firstFrameHostTime: 2_000)
        #expect(anchor.latest() == .init(frame: 512, hostTime: 2_000))
    }

    @Test func hostClockRateIsPositive() {
        #expect(MicAlignment.hostTicksPerSecond > 1_000_000)
    }
}
