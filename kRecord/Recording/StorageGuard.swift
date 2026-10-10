import Foundation

enum StorageError: Error, Equatable, Sendable {
    case cannotCreateFolder(URL)
    case folderNotWritable(URL)
    /// The folder disappeared during a recording, e.g. its external drive was ejected.
    case folderUnavailable(URL)
    /// Free space fell below the reserve needed to finish the recording.
    case diskFull
}

/// Guards the destination folder before and during a recording (design D7).
protocol StorageGuard: Sendable {
    /// Creates the folder if needed and verifies it can be written to and has free space.
    func prepare(_ folder: URL) throws(StorageError)

    /// Checks the folder periodically during a recording. Yields the first problem, then ends.
    func monitor(_ folder: URL) -> AsyncStream<StorageError>
}

struct FileSystemStorageGuard: StorageGuard {
    /// Room left for finalization (conversion of the intermediates) when the disk fills up.
    static let defaultReserveBytes: Int64 = 500_000_000

    /// Available bytes on the volume of a URL, or `nil` when unknown.
    typealias CapacityProvider = @Sendable (URL) -> Int64?

    var reserveBytes: Int64 = Self.defaultReserveBytes
    var interval: Duration = .seconds(5)
    var capacity: CapacityProvider = { Self.volumeAvailableCapacity($0) }

    static func volumeAvailableCapacity(_ url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    func prepare(_ folder: URL) throws(StorageError) {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory) {
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                throw .cannotCreateFolder(folder)
            }
        } else if !isDirectory.boolValue {
            throw .cannotCreateFolder(folder)
        }

        let probe = folder.appending(path: ".kRecord-write-probe-\(UUID().uuidString)")
        do {
            try Data().write(to: probe)
            try fileManager.removeItem(at: probe)
        } catch {
            try? fileManager.removeItem(at: probe)
            throw .folderNotWritable(folder)
        }

        if let problem = check(folder) { throw problem }
    }

    /// One check of the conditions monitored during a recording.
    func check(_ folder: URL) -> StorageError? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .folderUnavailable(folder)
        }
        if let available = capacity(folder), available < reserveBytes {
            return .diskFull
        }
        return nil
    }

    func monitor(_ folder: URL) -> AsyncStream<StorageError> {
        let (stream, continuation) = AsyncStream<StorageError>.makeStream()
        let task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { break }
                if let problem = check(folder) {
                    continuation.yield(problem)
                    break
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}
