import Synchronization

/// Lock-free single-producer/single-consumer ring buffer of interleaved `Float` frames (design D4).
///
/// The producer side (`write`) is real-time safe: no allocation, locks, or system calls. Writes are
/// all-or-nothing per call so frames are never split; a write that does not fit is dropped and
/// counted in `droppedFrames`, which lets the consumer pad the timeline and keep sources aligned.
///
/// Exactly one thread may call `write` and exactly one (other) thread may call `read`.
final class RingBuffer: @unchecked Sendable {
    let channels: Int
    let capacityFrames: Int

    private let storage: UnsafeMutablePointer<Float>
    // Monotonic frame counters; slot = counter % capacityFrames.
    private let writeCounter = Atomic<Int>(0)
    private let readCounter = Atomic<Int>(0)
    private let dropped = Atomic<Int>(0)

    init(channels: Int, capacityFrames: Int) {
        precondition(channels > 0 && capacityFrames > 0)
        self.channels = channels
        self.capacityFrames = capacityFrames
        storage = .allocate(capacity: channels * capacityFrames)
        storage.initialize(repeating: 0, count: channels * capacityFrames)
    }

    deinit {
        storage.deallocate()
    }

    /// Frames written but not yet read. Safe to call from either side.
    var availableFrames: Int {
        writeCounter.load(ordering: .acquiring) - readCounter.load(ordering: .acquiring)
    }

    /// Total frames dropped by the producer because the buffer was full.
    var droppedFrames: Int {
        dropped.load(ordering: .relaxed)
    }

    // MARK: Producer

    /// Copies `frameCount` frames from `source`, an interleaved buffer with `sourceChannels` channels
    /// per frame, taking its first `channels` channels. Returns `false` and drops the whole write
    /// if it does not fit.
    @discardableResult
    func write(_ source: UnsafePointer<Float>, frameCount: Int, sourceChannels: Int) -> Bool {
        precondition(sourceChannels >= channels)
        guard frameCount > 0 else { return true }
        let writeIndex = writeCounter.load(ordering: .relaxed)
        let readIndex = readCounter.load(ordering: .acquiring)
        guard capacityFrames - (writeIndex - readIndex) >= frameCount else {
            dropped.add(frameCount, ordering: .relaxed)
            return false
        }

        var start = writeIndex % capacityFrames
        var copied = 0
        while copied < frameCount {
            let run = min(frameCount - copied, capacityFrames - start)
            let destination = storage + start * channels
            let from = source + copied * sourceChannels
            if sourceChannels == channels {
                destination.update(from: from, count: run * channels)
            } else {
                for frame in 0..<run {
                    for channel in 0..<channels {
                        destination[frame * channels + channel] = from[frame * sourceChannels + channel]
                    }
                }
            }
            copied += run
            start = 0
        }
        writeCounter.store(writeIndex + frameCount, ordering: .releasing)
        return true
    }

    // MARK: Consumer

    /// Copies up to `maxFrames` interleaved frames into `destination` and returns the number copied.
    @discardableResult
    func read(into destination: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        let readIndex = readCounter.load(ordering: .relaxed)
        let writeIndex = writeCounter.load(ordering: .acquiring)
        let frameCount = min(maxFrames, writeIndex - readIndex)
        guard frameCount > 0 else { return 0 }

        var start = readIndex % capacityFrames
        var copied = 0
        while copied < frameCount {
            let run = min(frameCount - copied, capacityFrames - start)
            (destination + copied * channels).update(from: storage + start * channels, count: run * channels)
            copied += run
            start = 0
        }
        readCounter.store(readIndex + frameCount, ordering: .releasing)
        return frameCount
    }
}
