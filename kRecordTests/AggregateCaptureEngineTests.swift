import CoreAudio
import Foundation
import Testing
@testable import kRecord

struct AggregateCaptureEngineTests {
    /// A recording without the microphone source must not open any input device, also when the
    /// Mac has a default input (it would otherwise become the aggregate's clock).
    @Test func noInputCandidateWithoutMicrophone() {
        #expect(AggregateCaptureEngine.inputCandidates(nil, sources: .system) == [nil])
        #expect(AggregateCaptureEngine.inputCandidates(42, sources: .system) == [nil])
    }

    @Test func microphoneCandidatesStartWithTheResolvedDevice() {
        let candidates = AggregateCaptureEngine.inputCandidates(42, sources: .all)
        #expect(candidates.first == 42)
        // System audio keeps the recording going without a microphone as the last resort.
        #expect(candidates.last == .some(nil))
        #expect(AggregateCaptureEngine.inputCandidates(42, sources: .microphone).contains(nil) == false)
    }
}
