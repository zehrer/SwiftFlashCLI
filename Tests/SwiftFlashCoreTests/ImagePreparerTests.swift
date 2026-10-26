import Compression
import Foundation
import Testing
@testable import SwiftFlashCore

struct ImagePreparerTests {
    @Test
    func plainLocalImageNeedsNoTemporaryFiles() async throws {
        let directory = try ImagePreparer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("plain.img")
        try Data(count: 1024 * 1024).write(to: imageURL)

        let prepared = try await ImagePreparer().prepare(source: imageURL.path) { _, _, _ in }

        #expect(prepared.hasTemporaryFiles == false)
        #expect(prepared.image.url.path == imageURL.path)
        #expect(prepared.image.sourceLocation == nil)
    }

    @Test
    func localXZImageIsDecompressedAndCleanedUp() async throws {
        let directory = try ImagePreparer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var payload = Data(count: 2 * 1024 * 1024)
        for index in stride(from: 0, to: payload.count, by: 4096) {
            payload[index] = UInt8(truncatingIfNeeded: index / 4096)
        }
        let compressedURL = directory.appendingPathComponent("disk.img.xz")
        try encodeXZ(payload).write(to: compressedURL)

        let prepared = try await ImagePreparer().prepare(source: compressedURL.path) { _, _, _ in }

        #expect(prepared.image.name == "disk.img")
        #expect(prepared.image.size == Int64(payload.count))
        #expect(prepared.image.sourceLocation == compressedURL.path)
        #expect(try Data(contentsOf: prepared.image.url) == payload)

        prepared.cleanup()
        #expect(!FileManager.default.fileExists(atPath: prepared.image.url.path))
        #expect(FileManager.default.fileExists(atPath: compressedURL.path))
    }

    @Test
    func corruptXZImageFailsWithoutLeavingFiles() async throws {
        let directory = try ImagePreparer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let compressedURL = directory.appendingPathComponent("broken.img.xz")
        try Data(repeating: 0x42, count: 4096).write(to: compressedURL)

        await #expect(throws: FlashError.self) {
            _ = try await ImagePreparer().prepare(source: compressedURL.path) { _, _, _ in }
        }
    }

    @Test
    func unsupportedImageNameIsRejected() {
        #expect(throws: FlashError.self) { try ImageSupport.validateImageName("image.zip") }
        #expect(throws: FlashError.self) { try ImageSupport.validateImageName("notes.txt.xz") }
        #expect(throws: Never.self) { try ImageSupport.validateImageName("sdcard-redox.img.xz") }
        #expect(throws: Never.self) { try ImageSupport.validateImageName("installer.ISO") }
    }

    @Test
    func remoteSourcesAreDetected() {
        #expect(ImagePreparer.isRemote("http://192.168.178.120:8080/redox/sdcard-redox.img.xz"))
        #expect(ImagePreparer.isRemote("HTTPS://example.com/a.iso"))
        #expect(!ImagePreparer.isRemote("/tmp/a.iso"))
    }

    /// Set SWIFTFLASH_TEST_IMAGE_URL to an http(s) image (optionally .xz) to exercise a real download.
    /// Optionally set SWIFTFLASH_TEST_IMAGE_SHA256 to the SHA-256 of the uncompressed image.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SWIFTFLASH_TEST_IMAGE_URL"] != nil))
    func remoteImageIsDownloadedAndCleanedUp() async throws {
        let source = try #require(ProcessInfo.processInfo.environment["SWIFTFLASH_TEST_IMAGE_URL"])

        let prepared = try await ImagePreparer().prepare(source: source) { _, _, _ in }

        #expect(prepared.hasTemporaryFiles)
        #expect(prepared.image.sourceLocation == source)
        #expect(prepared.image.size >= 1024 * 1024)
        if let expectedSHA256 = ProcessInfo.processInfo.environment["SWIFTFLASH_TEST_IMAGE_SHA256"] {
            #expect(try ImageSupport.calculateSHA256(for: prepared.image.url) == expectedSHA256.lowercased())
        }
        prepared.cleanup()
        #expect(!FileManager.default.fileExists(atPath: prepared.temporaryDirectory!.path))
    }

    private func encodeXZ(_ data: Data) throws -> Data {
        let capacity = data.count + 64 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }
        let size = data.withUnsafeBytes { raw in
            compression_encode_buffer(
                destination,
                capacity,
                raw.bindMemory(to: UInt8.self).baseAddress!,
                data.count,
                nil,
                COMPRESSION_LZMA
            )
        }
        try #require(size > 0)
        return Data(bytes: destination, count: size)
    }
}
