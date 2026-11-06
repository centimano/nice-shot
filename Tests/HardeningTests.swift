import Testing
import AppKit
@testable import NiceShot

/// File-handling safeguards from the security pass: saves never clobber an
/// existing file, and share-sheet staging stays private and gets cleaned up.
@MainActor
struct HardeningTests {
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("niceshot-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func noOverwriteWriteLeavesExistingFileAlone() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("taken.png")
        try Data("keep me".utf8).write(to: url)

        let outcome = Exporter.write(image: makeTestImage(), scale: 1, to: url, options: .withoutOverwriting)
        guard case .alreadyExists = outcome else {
            Issue.record("expected .alreadyExists, got \(outcome)")
            return
        }
        #expect(try Data(contentsOf: url) == Data("keep me".utf8))
    }

    @Test func atomicWriteReplacesWithCompleteImage() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("shot.png")
        try Data("old".utf8).write(to: url)

        let outcome = Exporter.write(image: makeTestImage(width: 40, height: 20), scale: 1, to: url, options: .atomic)
        guard case .written = outcome else {
            Issue.record("expected .written, got \(outcome)")
            return
        }
        let rep = try #require(NSBitmapImageRep(data: try Data(contentsOf: url)))
        #expect(rep.pixelsWide == 40)
    }

    @Test func quickSaveNeverReusesAName() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(Exporter.quickSave(image: makeTestImage(), scale: 1, in: folder))
        #expect(Exporter.quickSave(image: makeTestImage(), scale: 1, in: folder))
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(files.count == 2)
        #expect(Set(files).count == 2)
    }

    @Test func shareStagingIsPrivate() throws {
        let root = try makeFolder().appendingPathComponent("share", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let url = try #require(ShareFiles.write(Data("png".utf8), named: "Screenshot.png", in: root))
        #expect(url.lastPathComponent == "Screenshot.png")
        #expect(try Data(contentsOf: url) == Data("png".utf8))

        let fm = FileManager.default
        let fileMode = try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        let folderMode = try fm.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? Int
        #expect(fileMode == 0o600)
        #expect(folderMode == 0o700)

        // Two shares with the same name don't collide.
        let second = try #require(ShareFiles.write(Data("png2".utf8), named: "Screenshot.png", in: root))
        #expect(second != url)
        #expect(try Data(contentsOf: url) == Data("png".utf8))
    }

    @Test func sharePurgeKeepsRecentAndRemovesOld() throws {
        let root = try makeFolder().appendingPathComponent("share", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let recent = try #require(ShareFiles.write(Data("a".utf8), named: "a.png", in: root))

        // An hour from now the file is stale.
        ShareFiles.purge(olderThan: ShareFiles.maxAge, now: Date(), in: root)
        #expect(FileManager.default.fileExists(atPath: recent.path))
        ShareFiles.purge(olderThan: ShareFiles.maxAge, now: Date().addingTimeInterval(ShareFiles.maxAge + 60), in: root)
        #expect(!FileManager.default.fileExists(atPath: recent.path))

        // purge() with no age clears everything.
        let another = try #require(ShareFiles.write(Data("b".utf8), named: "b.png", in: root))
        ShareFiles.purge(in: root)
        #expect(!FileManager.default.fileExists(atPath: another.path))
    }
}
