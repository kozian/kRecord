import Foundation
import Testing
@testable import kRecord

struct FileNamingTests {
    private let moscow = TimeZone(identifier: "Europe/Moscow")!
    private let base = "kRecord 2026-10-10 14-30-05"

    /// 2026-10-10 14:30:05 in Moscow (UTC+3).
    private var start: Date {
        var components = DateComponents(year: 2026, month: 10, day: 10, hour: 14, minute: 30, second: 5)
        components.timeZone = moscow
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @Test func baseNameUsesLocalStartTime() {
        #expect(FileNaming.baseName(for: start, timeZone: moscow) == base)
        #expect(FileNaming.baseName(for: start, timeZone: TimeZone(identifier: "UTC")!) == "kRecord 2026-10-10 11-30-05")
    }

    @Test func mixedFileNames() {
        #expect(FileNaming.fileName(base: base, role: .mixed, fileExtension: "m4a") == "kRecord 2026-10-10 14-30-05.m4a")
        #expect(FileNaming.fileName(base: base, role: .mixed, fileExtension: "aac") == "kRecord 2026-10-10 14-30-05.aac")
    }

    @Test func separateFileNames() {
        #expect(FileNaming.fileName(base: base, role: .microphone, fileExtension: "m4a") == "kRecord 2026-10-10 14-30-05 (mic).m4a")
        #expect(FileNaming.fileName(base: base, role: .system, fileExtension: "m4a") == "kRecord 2026-10-10 14-30-05 (system).m4a")
    }

    @Test func noCollisionKeepsBase() {
        #expect(FileNaming.availableBase(base, roles: [.mixed]) { _ in false } == base)
    }

    @Test func collisionAppendsNumber() {
        let existing: Set = ["\(base).m4a", "\(base) 2.m4a"]
        #expect(FileNaming.availableBase(base, roles: [.mixed]) { existing.contains($0) } == "\(base) 3")
    }

    /// The `.aac` stream becomes an `.m4a` of the same name, so either extension takes the name.
    @Test func eitherExtensionTakesTheName() {
        #expect(FileNaming.availableBase(base, roles: [.mixed]) { $0 == "\(base).aac" } == "\(base) 2")
        #expect(FileNaming.availableBase(base, roles: [.mixed]) { $0 == "\(base).m4a" } == "\(base) 2")
        #expect(FileNaming.availableBase(base, roles: [.mixed]) { $0 == "\(base).wav" } == base)
    }

    @Test func separateFilesShareOneNumber() {
        // Only the system file collides, but both files move to number 2.
        let existing: Set = ["\(base) (system).m4a"]
        let available = FileNaming.availableBase(base, roles: [.microphone, .system]) { existing.contains($0) }
        #expect(available == "\(base) 2")
        #expect(FileNaming.fileName(base: available, role: .microphone, fileExtension: "m4a") == "\(base) 2 (mic).m4a")
    }

    @Test func availableBaseChecksDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "FileNamingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory.appending(path: "\(base).aac"))
        #expect(FileNaming.availableBase(in: directory, base: base, roles: [.mixed]) == "\(base) 2")
    }
}
