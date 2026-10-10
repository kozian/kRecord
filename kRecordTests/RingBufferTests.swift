import Foundation
import Testing
@testable import kRecord

struct RingBufferTests {
    @Test func readsBackWhatWasWritten() {
        let ring = RingBuffer(channels: 2, capacityFrames: 8)
        let input: [Float] = [1, 2, 3, 4, 5, 6]
        #expect(ring.write(input, frameCount: 3, sourceChannels: 2))
        #expect(ring.availableFrames == 3)

        var output = [Float](repeating: 0, count: 6)
        #expect(ring.read(into: &output, maxFrames: 10) == 3)
        #expect(output == input)
        #expect(ring.availableFrames == 0)
    }

    @Test func wrapsAroundTheEnd() {
        let ring = RingBuffer(channels: 1, capacityFrames: 4)
        var output = [Float](repeating: 0, count: 4)
        ring.write([1, 2, 3], frameCount: 3, sourceChannels: 1)
        #expect(ring.read(into: &output, maxFrames: 2) == 2)
        #expect(output.prefix(2) == [1, 2])

        // Write position is now at slot 3; these frames wrap to slots 3, 0, 1.
        #expect(ring.write([4, 5, 6], frameCount: 3, sourceChannels: 1))
        #expect(ring.availableFrames == 4)
        #expect(ring.read(into: &output, maxFrames: 4) == 4)
        #expect(output == [3, 4, 5, 6])
    }

    @Test func dropsWholeWriteWhenFull() {
        let ring = RingBuffer(channels: 1, capacityFrames: 4)
        #expect(ring.write([1, 2, 3], frameCount: 3, sourceChannels: 1))
        #expect(!ring.write([4, 5], frameCount: 2, sourceChannels: 1))
        #expect(ring.droppedFrames == 2)
        #expect(ring.availableFrames == 3)

        #expect(ring.write([6], frameCount: 1, sourceChannels: 1))
        var output = [Float](repeating: 0, count: 4)
        #expect(ring.read(into: &output, maxFrames: 4) == 4)
        #expect(output == [1, 2, 3, 6])
    }

    @Test func takesFirstChannelsFromWiderSource() {
        // A 3-channel interface recorded as mono uses its first channel.
        let ring = RingBuffer(channels: 1, capacityFrames: 4)
        ring.write([1, 10, 100, 2, 20, 200], frameCount: 2, sourceChannels: 3)
        var output = [Float](repeating: 0, count: 2)
        #expect(ring.read(into: &output, maxFrames: 2) == 2)
        #expect(output == [1, 2])
    }

    @Test func readFromEmptyBufferReturnsZero() {
        let ring = RingBuffer(channels: 2, capacityFrames: 4)
        var output = [Float](repeating: -1, count: 8)
        #expect(ring.read(into: &output, maxFrames: 4) == 0)
        #expect(output.allSatisfy { $0 == -1 })
    }

    /// Producer and consumer on separate threads: every frame arrives exactly once and in order,
    /// and frames are either delivered or counted as dropped.
    @Test func concurrentProducerAndConsumer() async {
        let ring = RingBuffer(channels: 2, capacityFrames: 1024)
        let totalFrames = 2_000_000
        let chunkSizes = [1, 7, 64, 255, 512, 33]

        let producer = Task.detached {
            var chunk = [Float](repeating: 0, count: 512 * 2)
            var next = 0
            var produced = 0
            var chunkIndex = 0
            while next < totalFrames {
                let frames = min(chunkSizes[chunkIndex % chunkSizes.count], totalFrames - next)
                chunkIndex += 1
                for i in 0..<frames {
                    chunk[i * 2] = Float(next + i)
                    chunk[i * 2 + 1] = -Float(next + i)
                }
                if ring.write(chunk, frameCount: frames, sourceChannels: 2) { produced += frames }
                next += frames
            }
            return produced
        }

        let consumer = Task.detached {
            var buffer = [Float](repeating: 0, count: 300 * 2)
            var received = 0
            var last = -1
            var ordered = true
            while true {
                let count = ring.read(into: &buffer, maxFrames: 300)
                for i in 0..<count {
                    let value = Int(buffer[i * 2])
                    if value <= last || buffer[i * 2 + 1] != -buffer[i * 2] { ordered = false }
                    last = value
                }
                received += count
                if count == 0 {
                    if last == totalFrames - 1 || received + ring.droppedFrames >= totalFrames { break }
                    await Task.yield()
                }
            }
            return (received, ordered)
        }

        let produced = await producer.value
        let (received, ordered) = await consumer.value
        #expect(ordered)
        #expect(received == produced)
        #expect(received + ring.droppedFrames == totalFrames)
    }
}
