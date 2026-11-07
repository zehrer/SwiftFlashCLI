import Foundation
import Testing
@testable import SwiftFlashCore

struct ImageSourcesTests {
    private let base = URL(string: "http://homenodellm:8080/sdcard/")!

    @Test
    func splitsFamilyAndVersionForBothNamingSchemes() {
        #expect(RemoteImageNaming.split(fileName: "redox-rpi-t18-direct-v0.4.0-dev-36-g1107e5f7+x95e1.img.xz")
            == ("redox-rpi-t18-direct", "v0.4.0-dev-36-g1107e5f7+x95e1"))
        #expect(RemoteImageNaming.split(fileName: "redox-rpi-bootcode-monitor-3bp-20261107b.img.xz")
            == ("redox-rpi-bootcode-monitor-3bp", "20261107b"))
        #expect(RemoteImageNaming.split(fileName: "redox-rpi-v0.3.0-rc4.img") == ("redox-rpi", "v0.3.0-rc4"))
        #expect(RemoteImageNaming.split(fileName: "installer.iso") == ("installer", nil))
    }

    @Test
    func parsesPythonDirectoryListing() {
        let html = """
        <ul>
        <li><a href="redox-rpi-t18-direct-v0.4.0-dev-36-g1107e5f7%2Bx95e1.img.xz">x</a></li>
        <li><a href="redox-rpi-t18-direct-v0.4.0-dev-36-g1107e5f7%2Bx95e1.img.xz.sha256">x</a></li>
        <li><a href="redox-rpi-t18-direct-v0.4.0-dev-36-g1107e5f7%2Bx95e1.manifest.toml">x</a></li>
        <li><a href="redox-rpi-bootcode-monitor-3bp-20261107b.img.xz">x</a></li>
        <li><a href="models/">models/</a></li>
        <li><a href="../">..</a></li>
        </ul>
        """

        let images = ImageSourceBrowser.parseDirectoryListing(html, base: base)

        #expect(images.map(\.fileName) == [
            "redox-rpi-t18-direct-v0.4.0-dev-36-g1107e5f7+x95e1.img.xz",
            "redox-rpi-bootcode-monitor-3bp-20261107b.img.xz",
        ])
        #expect(images[0].url.absoluteString
            == "http://homenodellm:8080/sdcard/redox-rpi-t18-direct-v0.4.0-dev-36-g1107e5f7%2Bx95e1.img.xz")
        #expect(images[0].family == "redox-rpi-t18-direct")
    }

    @Test
    func parsesIndexJSON() throws {
        let json = Data("""
        {"images": [
          {"file": "redox-rpi-t18-direct-v0.4.0-dev-36-g1107e5f7+x95e1.img.xz", "date": "2026-11-02T20:50:32Z"},
          {"file": "fastnet-db5ea27.img.xz", "family": "redox-rpi-zero2w-fastnet", "version": "db5ea27"},
          {"file": "notes.txt"}
        ]}
        """.utf8)

        let images = try #require(ImageSourceBrowser.parseIndex(json, base: base))

        #expect(images.count == 2)
        #expect(images[0].family == "redox-rpi-t18-direct")
        #expect(images[0].date == ISO8601DateFormatter().date(from: "2026-11-02T20:50:32Z"))
        #expect(images[1].family == "redox-rpi-zero2w-fastnet")
        #expect(images[1].version == "db5ea27")
        #expect(ImageSourceBrowser.parseIndex(Data("<html>".utf8), base: base) == nil)
    }

    @Test
    func newestBuildIsFirstByDateThenName() {
        let older = image("fam-v1.0.img.xz", date: Date(timeIntervalSince1970: 100))
        let newer = image("fam-v0.9.img.xz", date: Date(timeIntervalSince1970: 200))
        let undated = image("fam-v2.0.img.xz", date: nil)
        let byName10 = image("other-v1.10.img.xz", date: nil)
        let byName9 = image("other-v1.9.img.xz", date: nil)

        let families = RemoteImageNaming.families(from: [older, undated, newer, byName9, byName10])

        #expect(families.map(\.name) == ["fam", "other"])
        #expect(families[0].builds.map(\.fileName) == ["fam-v0.9.img.xz", "fam-v1.0.img.xz", "fam-v2.0.img.xz"])
        #expect(families[1].newest.fileName == "other-v1.10.img.xz")
    }

    @Test
    func familyQueryMatchesExactSuffixOrUniqueSubstring() throws {
        let families = RemoteImageNaming.families(from: [
            image("redox-rpi-bootcode-monitor-3bp-20261107b.img.xz", date: nil),
            image("redox-rpi-bootcode-m1-3bp-20261107.img.xz", date: nil),
            image("redox-rpi-t18-direct-v0.4.0.img.xz", date: nil),
        ])

        #expect(try RemoteImageNaming.family(matching: "redox-rpi-t18-direct", in: families).name == "redox-rpi-t18-direct")
        #expect(try RemoteImageNaming.family(matching: "bootcode-monitor-3bp", in: families).name == "redox-rpi-bootcode-monitor-3bp")
        #expect(try RemoteImageNaming.family(matching: "t18", in: families).name == "redox-rpi-t18-direct")
        #expect(throws: FlashError.self) { try RemoteImageNaming.family(matching: "3bp", in: families) }
        #expect(throws: FlashError.self) { try RemoteImageNaming.family(matching: "nothing", in: families) }
    }

    @Test
    func referencesNeedAKnownSource() {
        let sources = [ImageSource(name: "redox", url: "http://homenodellm:8080/sdcard")]
        #expect(ImageSourceReference.parse("redox:t18", sources: sources) == ImageSourceReference(sourceName: "redox", family: "t18"))
        #expect(ImageSourceReference.parse("redox:", sources: sources) == ImageSourceReference(sourceName: "redox", family: ""))
        #expect(ImageSourceReference.parse("other:t18", sources: sources) == nil)
        #expect(ImageSourceReference.parse("http://homenodellm:8080/a.img", sources: sources) == nil)
        #expect(ImageSourceReference.parse("/tmp/a.img", sources: sources) == nil)
        #expect(sources[0].directoryURL?.absoluteString == "http://homenodellm:8080/sdcard/")
    }

    @Test
    func sourceStoreValidatesAndReplaces() throws {
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: configURL) }
        let store = ImageSourceStore(configStore: try AppConfigStore(configURL: configURL))

        try store.add(ImageSource(name: "redox", url: "http://old/"))
        try store.add(ImageSource(name: "redox", url: "http://homenodellm:8080/sdcard/"))
        #expect(store.allSources() == [ImageSource(name: "redox", url: "http://homenodellm:8080/sdcard/")])
        #expect(throws: FlashError.self) { try store.add(ImageSource(name: "bad name", url: "http://x/")) }
        #expect(throws: FlashError.self) { try store.add(ImageSource(name: "local", url: "/tmp/images")) }
        #expect(try store.remove(named: "redox"))
        #expect(try !store.remove(named: "redox"))
    }

    @Test
    func parsesHTTPDates() {
        #expect(ImageSourceBrowser.parseHTTPDate("Mon, 02 Nov 2026 20:50:32 GMT")
            == ISO8601DateFormatter().date(from: "2026-11-02T20:50:32Z"))
        #expect(ImageSourceBrowser.parseHTTPDate("yesterday") == nil)
    }

    private func image(_ fileName: String, date: Date?) -> RemoteImage {
        let (family, version) = RemoteImageNaming.split(fileName: fileName)
        return RemoteImage(fileName: fileName, url: base.appendingPathComponent(fileName), family: family, version: version, date: date)
    }
}
