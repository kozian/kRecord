import Foundation
import Testing
@testable import kRecord

struct FakeCaptureEngineTests {
    @Test func producesDeterministicAlignedFrames() async throws {
        let engine = FakeCaptureEngine()
        let streams = try await engine.start(CaptureConfiguration(inputDeviceUID: nil, sources: .all))
        engine.pump(frames: 100)
        engine.pump(frames: 50)

        let mic = try #require(streams.microphone)
        let system = try #require(streams.system)
        #expect(mic.availableFrames == 150)
        #expect(system.availableFrames == 150)

        var micFrames = [Float](repeating: 0, count: 150)
        var systemFrames = [Float](repeating: 0, count: 300)
        mic.read(into: &micFrames, maxFrames: 150)
        system.read(into: &systemFrames, maxFrames: 150)
        for n in 0..<150 {
            #expect(micFrames[n] == FakeCaptureEngine.micSample(n))
            #expect(systemFrames[n * 2] == FakeCaptureEngine.systemSample(n, channel: 0))
            #expect(systemFrames[n * 2 + 1] == FakeCaptureEngine.systemSample(n, channel: 1))
        }
        #expect(streams.levels.take().microphone.peak > 0)
    }

    @Test func capturesOnlyRequestedSources() async throws {
        let engine = FakeCaptureEngine()
        let streams = try await engine.start(CaptureConfiguration(inputDeviceUID: "usb-mic", sources: .system))
        #expect(streams.microphone == nil)
        #expect(streams.system != nil)
        #expect(engine.configurations == [CaptureConfiguration(inputDeviceUID: "usb-mic", sources: .system)])
    }

    @Test func injectedStartFailure() async {
        let engine = FakeCaptureEngine()
        engine.failNextStart(with: .noInputDevice)
        await #expect(throws: CaptureError.noInputDevice) {
            _ = try await engine.start(CaptureConfiguration(inputDeviceUID: nil, sources: .all))
        }
        #expect(!engine.isRunning)
    }

    @Test func eventsEndWhenCaptureStops() async throws {
        let engine = FakeCaptureEngine()
        _ = try await engine.start(CaptureConfiguration(inputDeviceUID: nil, sources: .all))
        let events = engine.events()
        engine.emit(.inputDeviceChanged(name: "Built-in Microphone"))
        await engine.stop()

        var received: [CaptureEvent] = []
        for await event in events { received.append(event) }
        #expect(received == [.inputDeviceChanged(name: "Built-in Microphone")])
        #expect(engine.stopCount == 1)
    }
}
