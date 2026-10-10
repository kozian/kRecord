import Foundation

/// Sandbox access to a user-chosen destination folder (design D10): security-scoped bookmarks and
/// the access calls around them. Injected so restoring a folder can be tested without a sandbox.
struct FolderAccess: Sendable {
    struct ResolvedBookmark: Sendable {
        var url: URL
        var isStale: Bool
    }

    var makeBookmark: @Sendable (URL) throws -> Data
    var resolveBookmark: @Sendable (Data) throws -> ResolvedBookmark
    var startAccessing: @Sendable (URL) -> Bool
    var stopAccessing: @Sendable (URL) -> Void
    var directoryExists: @Sendable (URL) -> Bool

    static let system = FolderAccess(
        makeBookmark: { url in
            try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        },
        resolveBookmark: { data in
            var isStale = false
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            return ResolvedBookmark(url: url, isStale: isStale)
        },
        startAccessing: { $0.startAccessingSecurityScopedResource() },
        stopAccessing: { $0.stopAccessingSecurityScopedResource() },
        directoryExists: { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        })
}

/// The outcome of restoring the stored custom destination folder at launch.
enum FolderRestoration: Equatable, Sendable {
    /// No custom folder is stored: the default folder is used.
    case noCustomFolder
    /// Access to the custom folder is active. `refreshedBookmark` replaces a stale stored bookmark.
    case restored(URL, refreshedBookmark: Data?)
    /// The stored folder cannot be used any more; revert to the default and tell the user.
    case unavailable

    /// Resolves `bookmark` and starts access to the folder. When the result is `.restored`, the caller
    /// owns the started access and must stop it when the folder is no longer used.
    static func restore(bookmark: Data?, access: FolderAccess) -> FolderRestoration {
        guard let bookmark else { return .noCustomFolder }
        guard let resolved = try? access.resolveBookmark(bookmark), access.startAccessing(resolved.url) else {
            return .unavailable
        }
        guard access.directoryExists(resolved.url) else {
            access.stopAccessing(resolved.url)
            return .unavailable
        }
        guard resolved.isStale else { return .restored(resolved.url, refreshedBookmark: nil) }
        // A stale bookmark still resolved, so access works; store a fresh one for the next launch.
        guard let refreshed = try? access.makeBookmark(resolved.url) else {
            access.stopAccessing(resolved.url)
            return .unavailable
        }
        return .restored(resolved.url, refreshedBookmark: refreshed)
    }
}
