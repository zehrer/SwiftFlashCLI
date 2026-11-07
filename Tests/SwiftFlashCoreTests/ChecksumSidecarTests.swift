import Foundation
import Testing
@testable import SwiftFlashCore

struct ChecksumSidecarTests {
    private let hash = "65b83ef4720375654f9f1dc276b8aa677b748589c9ee56ddc01ef2a9604f187b"

    @Test
    func parsesSha256sumOutputAndPlainHashes() {
        #expect(ChecksumSidecar.parse("\(hash)  redox-rpi-t18-direct-v0.4.0-dev-36-g1107e5f7+x95e1.img.xz\n") == hash)
        #expect(ChecksumSidecar.parse(hash.uppercased()) == hash)
        #expect(ChecksumSidecar.parse("  \(hash)\n") == hash)
        #expect(ChecksumSidecar.parse("<html>Not Found</html>") == nil)
        #expect(ChecksumSidecar.parse(String(hash.dropLast())) == nil)
        #expect(ChecksumSidecar.parse("") == nil)
    }

    @Test
    func sidecarURLKeepsFileName() throws {
        let url = try #require(URL(string: "http://homenodellm:8080/sdcard/redox-v0.4.0-dev-36-g1107e5f7+x95e1.img.xz"))
        #expect(
            ChecksumSidecar.sidecarURL(for: url).absoluteString
                == "http://homenodellm:8080/sdcard/redox-v0.4.0-dev-36-g1107e5f7+x95e1.img.xz.sha256"
        )
    }

    @Test
    func localImageWithMatchingSidecarIsVerified() async throws {
        let directory = try ImagePreparer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("disk.img")
        try Data(repeating: 7, count: 1024 * 1024).write(to: imageURL)
        let sha256 = try ImageSupport.calculateSHA256(for: imageURL)
        try Data("\(sha256)  disk.img\n".utf8).write(to: directory.appendingPathComponent("disk.img.sha256"))

        let prepared = try await ImagePreparer().prepare(source: imageURL.path) { _ in }

        #expect(prepared.checksumVerified)
    }

    @Test
    func localImageWithWrongSidecarIsRejected() async throws {
        let directory = try ImagePreparer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("disk.img")
        try Data(repeating: 7, count: 1024 * 1024).write(to: imageURL)
        try Data("\(hash)  disk.img\n".utf8).write(to: directory.appendingPathComponent("disk.img.sha256"))

        await #expect(throws: FlashError.self) {
            _ = try await ImagePreparer().prepare(source: imageURL.path) { _ in }
        }
    }

    @Test
    func localImageWithoutSidecarIsNotMarkedVerified() async throws {
        let directory = try ImagePreparer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("disk.img")
        try Data(repeating: 7, count: 1024 * 1024).write(to: imageURL)

        let prepared = try await ImagePreparer().prepare(source: imageURL.path) { _ in }

        #expect(!prepared.checksumVerified)
    }

    @Test
    func damagedTrashCopyIsNotUsedOffline() async throws {
        let directory = try ImagePreparer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let trashedFile = directory.appendingPathComponent("offline.img")
        try Data(count: 1024 * 1024).write(to: trashedFile)
        let store = TrashedDownloadStore(configStore: try AppConfigStore(configURL: directory.appendingPathComponent("config.json")))
        let source = "http://127.0.0.1:9/offline.img"
        try store.record(
            TrashedDownload(
                sourceURL: source,
                trashPath: trashedFile.path,
                size: 1024 * 1024,
                remote: RemoteFileInfo(size: 1024 * 1024, lastModified: "Mon"),
                downloadedAt: Date(),
                sha256: hash
            )
        )

        // The copy does not match the stored checksum, so a fresh download is attempted, which fails offline.
        await #expect(throws: FlashError.self) {
            _ = try await ImagePreparer(trashStore: store).prepare(source: source) { _ in }
        }
        #expect(FileManager.default.fileExists(atPath: trashedFile.path))
    }
}
