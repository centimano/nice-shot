import Testing
import AppKit
@testable import NiceShot

@MainActor
struct ExporterTests {
    private var fixedDate: Date {
        Calendar.current.date(
            from: DateComponents(year: 2026, month: 6, day: 11, hour: 9, minute: 5, second: 7)
        )!
    }

    @Test func defaultFileNameFormat() {
        #expect(Exporter.defaultFileName(date: fixedDate) == "Screenshot 2026-06-11 at 09.05.07.png")
    }

    @Test func defaultFileNameCounterSuffix() {
        #expect(Exporter.defaultFileName(date: fixedDate, counter: 1) == "Screenshot 2026-06-11 at 09.05.07 2.png")
    }

    @Test func pngDataPreservesPixelsAndDPI() throws {
        let image = makeTestImage(width: 200, height: 100)
        let data = try #require(Exporter.pngData(from: image, scale: 2))
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(rep.pixelsWide == 200)
        #expect(rep.pixelsHigh == 100)
        // Point size half the pixel size = the file declares 144 DPI (2×).
        #expect(abs(rep.size.width - 100) < 0.5)
        #expect(abs(rep.size.height - 50) < 0.5)
    }

    @Test func defaultFileNameHonorsExtension() {
        #expect(Exporter.defaultFileName(date: fixedDate, fileExtension: "jpg")
            == "Screenshot 2026-06-11 at 09.05.07.jpg")
    }

    @Test func jpegDataFlattensAlphaAndSetsDPI() throws {
        let image = makeTestImage(width: 200, height: 100)
        let data = try #require(Exporter.jpegData(from: image, scale: 2, quality: 0.85))
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(rep.pixelsWide == 200)
        #expect(rep.pixelsHigh == 100)
        #expect(!rep.hasAlpha)
        #expect(abs(rep.size.width - 100) < 0.5)
        #expect(abs(rep.size.height - 50) < 0.5)
        // JPEG magic bytes, so the file is what its extension claims.
        #expect(data.prefix(2) == Data([0xFF, 0xD8]))
    }

    @Test func imageFormatFromURL() {
        #expect(ImageFormat.from(url: URL(fileURLWithPath: "/tmp/a.png")) == .png)
        #expect(ImageFormat.from(url: URL(fileURLWithPath: "/tmp/a.jpg")) == .jpeg)
        #expect(ImageFormat.from(url: URL(fileURLWithPath: "/tmp/a.JPEG")) == .jpeg)
        #expect(ImageFormat.from(url: URL(fileURLWithPath: "/tmp/noext")) == .png)
    }

    @Test func uniqueDestinationAvoidsOverwriting() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("sds-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let first = Exporter.uniqueDestination(in: folder, date: fixedDate)
        #expect(first.lastPathComponent == "Screenshot 2026-06-11 at 09.05.07.png")

        FileManager.default.createFile(atPath: first.path, contents: Data())
        let second = Exporter.uniqueDestination(in: folder, date: fixedDate)
        #expect(second.lastPathComponent == "Screenshot 2026-06-11 at 09.05.07 2.png")

        FileManager.default.createFile(atPath: second.path, contents: Data())
        let third = Exporter.uniqueDestination(in: folder, date: fixedDate)
        #expect(third.lastPathComponent == "Screenshot 2026-06-11 at 09.05.07 3.png")
    }
}
