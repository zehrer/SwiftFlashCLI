import Compression
import Foundation

public enum ImagePreparationStep: Equatable, Sendable {
    case download
    case decompress
}

/// A flashable image plus the temporary files that were created to get it.
public struct PreparedImage: Equatable, Sendable {
    public var image: ImageDescriptor
    public var temporaryDirectory: URL?

    public init(image: ImageDescriptor, temporaryDirectory: URL?) {
        self.image = image
        self.temporaryDirectory = temporaryDirectory
    }

    public var hasTemporaryFiles: Bool {
        temporaryDirectory != nil
    }

    /// Removes downloaded or decompressed files. The original local source is never touched.
    public func cleanup() {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }
}

/// Turns an image source (local path or http(s) URL, optionally `.xz` compressed)
/// into a plain local image file that can be flashed.
public final class ImagePreparer: Sendable {
    public init() {}

    public static func isRemote(_ source: String) -> Bool {
        let lowercased = source.lowercased()
        return lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://")
    }

    public func prepare(
        source: String,
        progress: @escaping @Sendable (ImagePreparationStep, _ completedBytes: Int64, _ totalBytes: Int64) -> Void
    ) async throws -> PreparedImage {
        var temporaryDirectory: URL?
        do {
            var localURL: URL
            let sourceLocation: String

            if Self.isRemote(source) {
                guard let remoteURL = URL(string: source), !remoteURL.lastPathComponent.isEmpty else {
                    throw FlashError.invalidImage("Invalid image URL: \(source)")
                }
                try ImageSupport.validateImageName(remoteURL.lastPathComponent)
                let directory = try Self.makeTemporaryDirectory()
                temporaryDirectory = directory
                localURL = directory.appendingPathComponent(remoteURL.lastPathComponent)
                try await ImageDownloader.download(from: remoteURL, to: localURL) { completed, total in
                    progress(.download, completed, total)
                }
                sourceLocation = source
            } else {
                localURL = URL(fileURLWithPath: source)
                guard FileManager.default.fileExists(atPath: localURL.path) else {
                    throw FlashError.imageNotFound(localURL.path)
                }
                try ImageSupport.validateImageName(localURL.lastPathComponent)
                sourceLocation = localURL.path
            }

            if ImageSupport.isCompressed(localURL) {
                let directory = try temporaryDirectory ?? Self.makeTemporaryDirectory()
                temporaryDirectory = directory
                let decompressedURL = directory.appendingPathComponent(localURL.deletingPathExtension().lastPathComponent)
                try Self.decompressXZ(from: localURL, to: decompressedURL) { completed, total in
                    progress(.decompress, completed, total)
                }
                if Self.isRemote(source) {
                    try? FileManager.default.removeItem(at: localURL)
                }
                localURL = decompressedURL
            }

            var image = try ImageSupport.validateImage(at: localURL.path)
            if sourceLocation != image.url.path {
                image.sourceLocation = sourceLocation
            }
            return PreparedImage(image: image, temporaryDirectory: temporaryDirectory)
        } catch {
            if let temporaryDirectory {
                try? FileManager.default.removeItem(at: temporaryDirectory)
            }
            throw error
        }
    }

    static func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftflash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func decompressXZ(
        from source: URL,
        to destination: URL,
        progress: (_ consumedBytes: Int64, _ totalBytes: Int64) -> Void
    ) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw FlashError.ioFailed("Could not create \(destination.path)")
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let totalSize = max((attributes[.size] as? NSNumber)?.int64Value ?? 0, 1)

        let bufferSize = 4 * 1024 * 1024
        let sourceBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { sourceBuffer.deallocate() }
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destinationBuffer.deallocate() }

        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZMA) == COMPRESSION_STATUS_OK else {
            throw FlashError.invalidImage("Could not initialize xz decoder")
        }
        defer { compression_stream_destroy(stream) }

        stream.pointee.src_ptr = UnsafePointer(sourceBuffer)
        stream.pointee.src_size = 0
        var consumed: Int64 = 0
        var reachedEndOfInput = false

        while true {
            if stream.pointee.src_size == 0 && !reachedEndOfInput {
                let chunk = try input.read(upToCount: bufferSize) ?? Data()
                if chunk.isEmpty {
                    reachedEndOfInput = true
                } else {
                    chunk.copyBytes(to: sourceBuffer, count: chunk.count)
                    stream.pointee.src_ptr = UnsafePointer(sourceBuffer)
                    stream.pointee.src_size = chunk.count
                    consumed += Int64(chunk.count)
                    progress(consumed, totalSize)
                }
            }

            stream.pointee.dst_ptr = destinationBuffer
            stream.pointee.dst_size = bufferSize
            let flags = reachedEndOfInput ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            let status = compression_stream_process(stream, flags)

            let produced = bufferSize - stream.pointee.dst_size
            if produced > 0 {
                try output.write(contentsOf: Data(bytes: destinationBuffer, count: produced))
            }

            switch status {
            case COMPRESSION_STATUS_END:
                progress(totalSize, totalSize)
                return
            case COMPRESSION_STATUS_OK:
                if reachedEndOfInput && produced == 0 {
                    throw FlashError.invalidImage("xz image is truncated: \(source.lastPathComponent)")
                }
            default:
                throw FlashError.invalidImage("Could not decompress xz image: \(source.lastPathComponent)")
            }
        }
    }
}

private final class ImageDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var finishError: Error?

    private init(destination: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    static func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        let downloader = ImageDownloader(destination: destination, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: downloader, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            downloader.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let response = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            finishError = FlashError.ioFailed("Download failed with HTTP \(response.statusCode)")
            return
        }
        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            finishError = FlashError.ioFailed("Could not store download: \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result = error.map { FlashError.ioFailed("Download failed: \($0.localizedDescription)") } ?? finishError
        if let result {
            continuation?.resume(throwing: result)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}
