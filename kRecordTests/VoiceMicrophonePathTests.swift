import AVFoundation
import Testing
@testable import kRecord

struct VoiceMicrophonePathTests {
    private func makePath(alignsToSystem: Bool = true) -> (VoiceMicrophonePath, RingBuffer) {
        let ring = RingBuffer(channels: 1, capacityFrames: 48_000)
        return (VoiceMicrophonePath(ring: ring, alignsToSystem: alignsToSystem, sampleRate: 48_000), ring)
    }

    private func format(_ rate: Double) -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
    }

    @Test func converterFollowsEachNewInputFormat() {
        let (path, _) = makePath()
        path.prepare(inputFormat: format(48_000))
        #expect(path.convertsFrom == nil)
        path.prepare(inputFormat: format(44_100))
        #expect(path.convertsFrom == 44_100)
        path.prepare(inputFormat: format(16_000))
        #expect(path.convertsFrom == 16_000)
        path.prepare(inputFormat: format(48_000))
        #expect(path.convertsFrom == nil)
    }

    @Test func paddingWritesExactlyTheMissingFrames() {
        let (path, ring) = makePath()
        let timeline = TimelineAnchor()
        timeline.advance(frames: 1_000, firstFrameHostTime: 1)
        path.attach(timeline: timeline, levels: LevelSnapshot())
        path.padToTimeline()
        #expect(ring.availableFrames == 1_000)

        timeline.advance(frames: 512, firstFrameHostTime: 2)
        path.padToTimeline()
        #expect(ring.availableFrames == 1_512)
    }

    @Test func paddingWritesNothingWhenTheMicrophoneIsNotBehind() {
        let (path, ring) = makePath()
        let timeline = TimelineAnchor()
        timeline.advance(frames: 1_000, firstFrameHostTime: 1)
        path.attach(timeline: timeline, levels: LevelSnapshot())
        path.padToTimeline()
        path.padToTimeline()
        #expect(ring.availableFrames == 1_000)

        // Without a system timeline (microphone-only capture) there is nothing to pad to.
        let (unaligned, unalignedRing) = makePath(alignsToSystem: false)
        unaligned.padToTimeline()
        #expect(unalignedRing.availableFrames == 0)
    }
}
