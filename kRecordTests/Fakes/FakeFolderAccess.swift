import Foundation
import Synchronization
@testable import kRecord

/// Scriptable `FolderAccess`: bookmarks are the folder path encoded as data.
final class FakeFolderAccess: Sendable {
    struct State {
        var existingFolders: Set<String> = []
        var staleBookmarks: Set<Data> = []
        var unresolvable: Set<Data> = []
        var makeBookmarkFails = false
        var startFails = false
        var started: [URL] = []
        var stopped: [URL] = []
    }

    let state = Mutex(State())

    static func bookmark(for url: URL) -> Data { Data(url.path.utf8) }

    func addFolder(_ url: URL) {
        state.withLock { _ = $0.existingFolders.insert(url.path) }
    }

    func markStale(_ bookmark: Data) {
        state.withLock { _ = $0.staleBookmarks.insert(bookmark) }
    }

    func markUnresolvable(_ bookmark: Data) {
        state.withLock { _ = $0.unresolvable.insert(bookmark) }
    }

    func setMakeBookmarkFails(_ fails: Bool) {
        state.withLock { $0.makeBookmarkFails = fails }
    }

    func setStartFails(_ fails: Bool) {
        state.withLock { $0.startFails = fails }
    }

    var started: [URL] { state.withLock { $0.started } }
    var stopped: [URL] { state.withLock { $0.stopped } }

    /// Currently accessed folders: started minus stopped.
    var accessed: [URL] {
        state.withLock { state in
            var open = state.started
            for url in state.stopped { if let index = open.firstIndex(of: url) { open.remove(at: index) } }
            return open
        }
    }

    var folderAccess: FolderAccess {
        FolderAccess(
            makeBookmark: { [self] url in
                if state.withLock({ $0.makeBookmarkFails }) { throw CocoaError(.fileReadUnknown) }
                return Self.bookmark(for: url)
            },
            resolveBookmark: { [self] data in
                let (unresolvable, stale) = state.withLock { ($0.unresolvable.contains(data), $0.staleBookmarks.contains(data)) }
                if unresolvable { throw CocoaError(.fileNoSuchFile) }
                let path = String(decoding: data, as: UTF8.self)
                return FolderAccess.ResolvedBookmark(url: URL(fileURLWithPath: path, isDirectory: true), isStale: stale)
            },
            startAccessing: { [self] url in
                state.withLock { state in
                    if state.startFails { return false }
                    state.started.append(url)
                    return true
                }
            },
            stopAccessing: { [self] url in state.withLock { $0.stopped.append(url) } },
            directoryExists: { [self] url in state.withLock { $0.existingFolders.contains(url.path) } })
    }
}
