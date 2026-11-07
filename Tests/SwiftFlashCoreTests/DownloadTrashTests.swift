import Darwin
import Foundation
import Testing
@testable import SwiftFlashCore

struct DownloadTrashTests {
    @Test
    func trashedDownloadMatchesOnlyUnchangedFiles() {
        let byETag = trashedDownload(remote: RemoteFileInfo(size: 100, lastModified: "Mon", etag: "\"v1\""))
        #expect(byETag.matches(RemoteFileInfo(size: 100, lastModified: "Tue", etag: "\"v1\"")))
        #expect(!byETag.matches(RemoteFileInfo(size: 100, lastModified: "Mon", etag: "\"v2\"")))
        #expect(!byETag.matches(RemoteFileInfo(size: 101, lastModified: "Mon", etag: "\"v1\"")))

        let byDate = trashedDownload(remote: RemoteFileInfo(size: 100, lastModified: "Mon"))
        #expect(byDate.matches(RemoteFileInfo(size: 100, lastModified: "Mon")))
        #expect(!byDate.matches(RemoteFileInfo(size: 100, lastModified: "Tue")))

        let noValidators = trashedDownload(remote: RemoteFileInfo(size: 100))
        #expect(!noValidators.matches(RemoteFileInfo(size: 100)))
    }

    @Test
    func storeReplacesEntryForSameURL() throws {
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: configURL) }
        let store = TrashedDownloadStore(configStore: try AppConfigStore(configURL: configURL))

        try store.record(trashedDownload(trashPath: "/trash/a.img.xz"))
        try store.record(trashedDownload(trashPath: "/trash/a 2.img.xz"))

        #expect(store.entry(for: "http://host/a.img.xz")?.trashPath == "/trash/a 2.img.xz")
        let reloaded = TrashedDownloadStore(configStore: try AppConfigStore(configURL: configURL))
        #expect(reloaded.entry(for: "http://host/a.img.xz")?.trashPath == "/trash/a 2.img.xz")
        try reloaded.remove(sourceURL: "http://host/a.img.xz")
        #expect(reloaded.entry(for: "http://host/a.img.xz") == nil)
    }

    @Test
    func sudoMoveGoesToInvokingUsersTrashWithFinderStyleNames() throws {
        let home = try ImagePreparer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let trashDirectory = home.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        let env = ["HOME": home.path, "SUDO_UID": String(getuid()), "SUDO_GID": String(getgid())]

        var trashed: [URL] = []
        for _ in 0..<2 {
            let file = home.appendingPathComponent("sdcard-redox.img.xz")
            try Data("x".utf8).write(to: file)
            trashed.append(try UserTrash.move(file, env: env, effectiveUserID: 0))
        }

        #expect(trashed.map(\.lastPathComponent) == ["sdcard-redox.img.xz", "sdcard-redox 2.img.xz"])
        #expect(trashed.allSatisfy { $0.deletingLastPathComponent().path == trashDirectory.path })
        #expect(trashed.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test
    func trashedCopyIsUsedWhenServerIsUnreachable() async throws {
        let directory = try ImagePreparer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let trashedFile = directory.appendingPathComponent("offline.img")
        try Data(count: 1024 * 1024).write(to: trashedFile)

        let configURL = directory.appendingPathComponent("config.json")
        let store = TrashedDownloadStore(configStore: try AppConfigStore(configURL: configURL))
        // Port 9 (discard) is closed on a normal Mac, so the server check fails immediately.
        let source = "http://127.0.0.1:9/offline.img"
        try store.record(
            TrashedDownload(
                sourceURL: source,
                trashPath: trashedFile.path,
                size: 1024 * 1024,
                remote: RemoteFileInfo(size: 1024 * 1024, lastModified: "Mon"),
                downloadedAt: Date()
            )
        )

        let preparer = ImagePreparer(trashStore: store, trash: DownloadTrash { _ in
            Issue.record("A reused copy must not be trashed again")
            return directory
        })
        let prepared = try await preparer.prepare(source: source) { _ in }

        #expect(prepared.trashReuse?.verifiedWithServer == false)
        #expect(prepared.keptDownload == nil)
        #expect(prepared.image.sourceLocation == source)
        #expect(preparer.finish(prepared) == .removedTemporaryFiles)
        #expect(FileManager.default.fileExists(atPath: trashedFile.path))
    }

    /// Full round trip against a real server: set SWIFTFLASH_TEST_IMAGE_URL (see ImagePreparerTests).
    /// Set SWIFTFLASH_TEST_IMAGE_HAS_SHA256 if the server publishes `<image>.sha256` next to the image.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SWIFTFLASH_TEST_IMAGE_URL"] != nil))
    func remoteDownloadGoesToTrashAndIsReused() async throws {
        let source = try #require(ProcessInfo.processInfo.environment["SWIFTFLASH_TEST_IMAGE_URL"])
        let directory = try ImagePreparer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fakeTrash = directory.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
        let store = TrashedDownloadStore(configStore: try AppConfigStore(configURL: directory.appendingPathComponent("config.json")))
        let preparer = ImagePreparer(trashStore: store, trash: DownloadTrash { url in
            let destination = UserTrash.uniqueDestination(for: url.lastPathComponent, in: fakeTrash)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        })

        let first = try await preparer.prepare(source: source) { _ in }
        #expect(first.trashReuse == nil)
        let expectSidecar = ProcessInfo.processInfo.environment["SWIFTFLASH_TEST_IMAGE_HAS_SHA256"] != nil
        #expect(first.checksumVerified == expectSidecar)
        guard case .movedDownloadToTrash(let trashed) = preparer.finish(first) else {
            Issue.record("Download was not moved to the Trash")
            return
        }
        #expect(store.entry(for: source)?.trashPath == trashed.path)

        let second = try await preparer.prepare(source: source) { _ in }
        #expect(second.trashReuse?.verifiedWithServer == true)
        #expect(second.checksumVerified == expectSidecar)
        #expect(second.image.size == first.image.size)
        #expect(preparer.finish(second) == .removedTemporaryFiles)
        #expect(FileManager.default.fileExists(atPath: trashed.path))
    }

    private func trashedDownload(
        trashPath: String = "/trash/a.img.xz",
        remote: RemoteFileInfo = RemoteFileInfo(size: 100, lastModified: "Mon")
    ) -> TrashedDownload {
        TrashedDownload(
            sourceURL: "http://host/a.img.xz",
            trashPath: trashPath,
            size: 100,
            remote: remote,
            downloadedAt: Date()
        )
    }
}
