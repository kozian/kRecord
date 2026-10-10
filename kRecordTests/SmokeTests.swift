import Foundation
import Testing
@testable import kRecord

struct SmokeTests {
    @Test func testBundleLoadsApp() {
        #expect(Bundle.main.bundleIdentifier == "com.kozian.kRecord")
    }
}
