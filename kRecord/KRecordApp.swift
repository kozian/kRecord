import SwiftUI

@main
struct KRecordApp: App {
    init() {
        #if DEBUG
        DebugRecording.runIfRequested()
        #endif
    }

    var body: some Scene {
        Window("kRecord", id: "main") {
            Text("Ready to record")
                .frame(minWidth: 320, minHeight: 200)
        }
    }
}
