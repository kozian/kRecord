import Foundation
import Testing
@testable import kRecord

struct FileNamingTests {
    private let moscow = TimeZone(identifier: "Europe/Moscow")!

    /// 2026-10-10 14:30:05 in Moscow (UTC+3).
    private var start: Date {
        var components = DateComponents(year: 2026, month: 10, day: 10, hour: 14, minute: 30, second: 5)
        components.timeZone = moscow
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @Test func baseNameUsesLocalStartTime() {
        #expect(FileNaming.baseName(for: start, timeZone: moscow) == "kRecord 2026-10-10 14-30-05")
        #expect(FileNaming.baseName(for: start, timeZone: TimeZone(identifier: "UTC")!) == "kRecord 2026-10-10 11-30-05")
    }

    @Test func mixedFileName() {
        let base = FileNaming.baseName(for: start, timeZone: moscow)
        #expect(FileNaming.fileName(base: base, role: .mixed, fileExtension: OutputFormat.aac.fileExtension)
                == "kRecord 2026-10-10 14-30-05.m4a")
    }

    @Test func separateFileNames() {
        let base = "kRecord 2026-10-10 14-30-05"
        #expect(FileNaming.fileName(base: base, role: .microphone, fileExtension: "m4a") == "kRecord 2026-10-10 14-30-05 (mic).m4a")
        #expect(FileNaming.fileName(base: base, role: .system, fileExtension: "m4a") == "kRecord 2026-10-10 14-30-05 (system).m4a")
    }

    @Test func intermediateFileNames() {
        let base = "kRecord 2026-10-10 14-30-05"
        #expect(FileNaming.fileName(base: base, role: .recordingMicrophone, fileExtension: FileNaming.intermediateExtension)
                == "kRecord 2026-10-10 14-30-05 (recording mic).caf")
        #expect(FileNaming.fileName(base: base, role: .recordingSystem, fileExtension: FileNaming.intermediateExtension)
                == "kRecord 2026-10-10 14-30-05 (recording system).caf")
    }

    @Test func noCollisionKeepsName() {
        let names = FileNaming.uniqueFileNames(base: "kRecord 2026-10-10 14-30-05", roles: [.mixed], fileExtension: "m4a") { _ in false }
        #expect(names == ["kRecord 2026-10-10 14-30-05.m4a"])
    }

    @Test func collisionAppendsNumber() {
        let existing: Set = ["kRecord 2026-10-10 14-30-05.m4a", "kRecord 2026-10-10 14-30-05 2.m4a"]
        let names = FileNaming.uniqueFileNames(base: "kRecord 2026-10-10 14-30-05", roles: [.mixed], fileExtension: "m4a") {
            existing.contains($0)
        }
        #expect(names == ["kRecord 2026-10-10 14-30-05 3.m4a"])
    }

    @Test func separateFilesShareOneNumber() {
        // Only the system file collides, but both files move to number 2.
        let existing: Set = ["kRecord 2026-10-10 14-30-05 (system).wav"]
        let names = FileNaming.uniqueFileNames(base: "kRecord 2026-10-10 14-30-05", roles: [.microphone, .system],
                                               fileExtension: "wav") { existing.contains($0) }
        #expect(names == ["kRecord 2026-10-10 14-30-05 2 (mic).wav", "kRecord 2026-10-10 14-30-05 2 (system).wav"])
    }

    @Test func otherExtensionDoesNotCollide() {
        let existing: Set = ["kRecord 2026-10-10 14-30-05.wav"]
        let names = FileNaming.uniqueFileNames(base: "kRecord 2026-10-10 14-30-05", roles: [.mixed], fileExtension: "m4a") {
            existing.contains($0)
        }
        #expect(names == ["kRecord 2026-10-10 14-30-05.m4a"])
    }

    @Test func uniqueURLsChecksDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "FileNamingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory.appending(path: "kRecord 2026-10-10 14-30-05.m4a"))

        let urls = FileNaming.uniqueURLs(in: directory, base: "kRecord 2026-10-10 14-30-05", roles: [.mixed], fileExtension: "m4a")
        #expect(urls.map(\.lastPathComponent) == ["kRecord 2026-10-10 14-30-05 2.m4a"])
    }
}
