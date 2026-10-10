import Foundation
import Synchronization
import Testing
@testable import kRecord

struct StorageGuardTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "StorageGuardTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func plenty(_: URL) -> Int64? { 10_000_000_000 }

    @Test func createsMissingFolder() throws {
        let folder = root.appending(path: "Music/kRecord", directoryHint: .isDirectory)
        try FileSystemStorageGuard(capacity: plenty).prepare(folder)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        // The write probe is removed.
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func unwritableFolderIsRejected() throws {
        let folder = root.appending(path: "readonly", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

        #expect(throws: StorageError.folderNotWritable(folder)) {
            try FileSystemStorageGuard(capacity: plenty).prepare(folder)
        }
    }

    @Test func folderThatCannotBeCreatedIsRejected() throws {
        let parent = root.appending(path: "locked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path) }

        let folder = parent.appending(path: "kRecord", directoryHint: .isDirectory)
        #expect(throws: StorageError.cannotCreateFolder(folder)) {
            try FileSystemStorageGuard(capacity: plenty).prepare(folder)
        }
    }

    @Test func fileInPlaceOfFolderIsRejected() throws {
        let folder = root.appending(path: "notAFolder")
        try Data().write(to: folder)
        #expect(throws: StorageError.cannotCreateFolder(folder)) {
            try FileSystemStorageGuard(capacity: plenty).prepare(folder)
        }
    }

    @Test func lowFreeSpaceBlocksStart() {
        let guardian = FileSystemStorageGuard(capacity: { _ in 99_999_999 })
        #expect(throws: StorageError.diskFull) { try guardian.prepare(root) }
    }

    @Test func checkReportsDiskFullBelowReserve() {
        #expect(FileSystemStorageGuard(capacity: { _ in 100_000_000 }).check(root) == nil)
        #expect(FileSystemStorageGuard(capacity: { _ in 99_999_999 }).check(root) == .diskFull)
        #expect(FileSystemStorageGuard(capacity: { _ in nil }).check(root) == nil)
    }

    @Test func checkReportsRemovedFolder() throws {
        let folder = root.appending(path: "external", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let guardian = FileSystemStorageGuard(capacity: plenty)
        #expect(guardian.check(folder) == nil)
        try FileManager.default.removeItem(at: folder)
        #expect(guardian.check(folder) == .folderUnavailable(folder))
    }

    @Test func monitorYieldsFirstProblemThenEnds() async {
        final class Capacity: Sendable { let bytes = Atomic<Int64>(1_000_000_000) }
        let available = Capacity()
        let guardian = FileSystemStorageGuard(interval: .milliseconds(20),
                                              capacity: { _ in available.bytes.load(ordering: .relaxed) })
        let stream = guardian.monitor(root)
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            available.bytes.store(50_000_000, ordering: .relaxed)
        }
        var problems: [StorageError] = []
        for await problem in stream { problems.append(problem) }
        #expect(problems == [.diskFull])
    }

    @Test func realVolumeCapacityIsAvailable() {
        #expect((FileSystemStorageGuard.volumeAvailableCapacity(root) ?? 0) > 0)
    }
}
