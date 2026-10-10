import Foundation
import Testing
@testable import kRecord

struct FolderRestorationTests {
    private let folder = URL(fileURLWithPath: "/Volumes/Meetings/Recordings", isDirectory: true)
    private let access = FakeFolderAccess()

    private func bookmark() -> Data { FakeFolderAccess.bookmark(for: folder) }

    @Test func noBookmarkMeansDefaultFolder() {
        #expect(FolderRestoration.restore(bookmark: nil, access: access.folderAccess) == .noCustomFolder)
        #expect(access.started.isEmpty)
    }

    @Test func validBookmarkRestoresFolderAndKeepsAccess() {
        access.addFolder(folder)
        #expect(FolderRestoration.restore(bookmark: bookmark(), access: access.folderAccess)
                == .restored(folder, refreshedBookmark: nil))
        #expect(access.accessed == [folder])
    }

    @Test func unresolvableBookmarkIsUnavailable() {
        access.addFolder(folder)
        access.markUnresolvable(bookmark())
        #expect(FolderRestoration.restore(bookmark: bookmark(), access: access.folderAccess) == .unavailable)
        #expect(access.accessed.isEmpty)
    }

    @Test func deletedFolderIsUnavailableAndAccessIsReleased() {
        #expect(FolderRestoration.restore(bookmark: bookmark(), access: access.folderAccess) == .unavailable)
        #expect(access.started == [folder])
        #expect(access.accessed.isEmpty)
    }

    @Test func accessDeniedIsUnavailable() {
        access.addFolder(folder)
        access.setStartFails(true)
        #expect(FolderRestoration.restore(bookmark: bookmark(), access: access.folderAccess) == .unavailable)
    }

    /// A stale bookmark still resolves, so access works; it is refreshed for the next launch.
    @Test func staleBookmarkIsRefreshed() {
        access.addFolder(folder)
        access.markStale(bookmark())
        #expect(FolderRestoration.restore(bookmark: bookmark(), access: access.folderAccess)
                == .restored(folder, refreshedBookmark: bookmark()))
        #expect(access.accessed == [folder])
    }

    @Test func staleBookmarkThatCannotBeRefreshedIsUnavailable() {
        access.addFolder(folder)
        access.markStale(bookmark())
        access.setMakeBookmarkFails(true)
        #expect(FolderRestoration.restore(bookmark: bookmark(), access: access.folderAccess) == .unavailable)
        #expect(access.accessed.isEmpty)
    }
}
