import Compression
import Foundation

public enum ImagePreparationStep: Equatable, Sendable {
    case download
    case decompress
}

public struct ImagePreparationProgress: Equatable, Sendable {
    public var step: ImagePreparationStep
    /// Overall completion of the step, 0...1.
    public var fraction: Double
    /// Bytes downloaded, or bytes unpacked so far.
    public var processedBytes: Int64

    public init(step: ImagePreparationStep, fraction: Double, processedBytes: Int64) {
        self.step = step
        self.fraction = fraction
        self.processedBytes = processedBytes
    }
}

/// A freshly downloaded remote image that should go to the Trash for reuse instead of being deleted.
public struct KeptDownload: Equatable, Sendable {
    public var file: URL
    public var sourceURL: String
    public var remote: RemoteFileInfo
    /// SHA-256 of the downloaded file, kept so a later copy from the Trash can be checked offline.
    public var sha256: String
}

/// How a remote image was obtained from an earlier download in the Trash.
public struct TrashReuse: Equatable, Sendable {
    public var download: TrashedDownload
    /// False if the server was not reachable, so the copy could not be checked for being current.
    public var verifiedWithServer: Bool
}

/// What `ImagePreparer.finish` did with temporary files.
public enum ImageCleanupResult: Equatable, Sendable {
    case nothingToDo
    case removedTemporaryFiles
    case movedDownloadToTrash(URL)
    case trashFailed(String)
}

/// A flashable image plus the temporary files that were created to get it.
public struct PreparedImage: Equatable, Sendable {
    public var image: ImageDescriptor
    public var temporaryDirectory: URL?
    public var keptDownload: KeptDownload?
    public var trashReuse: TrashReuse?
    /// True if the image file (as downloaded or found, before unpacking) matched a published `.sha256`.
    public var checksumVerified: Bool

    public init(
        image: ImageDescriptor,
        temporaryDirectory: URL?,
        keptDownload: KeptDownload? = nil,
        trashReuse: TrashReuse? = nil,
        checksumVerified: Bool = false
    ) {
        self.image = image
        self.temporaryDirectory = temporaryDirectory
        self.keptDownload = keptDownload
        self.trashReuse = trashReuse
        self.checksumVerified = checksumVerified
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
///
/// With a `TrashedDownloadStore`, downloaded remote images are moved to the user's Trash after use
/// and taken from there next time, as long as the server still serves the same file.
public final class ImagePreparer {
    private let trashStore: TrashedDownloadStore?
    private let trash: DownloadTrash

    public init(trashStore: TrashedDownloadStore? = nil, trash: DownloadTrash = .userTrash) {
        self.trashStore = trashStore
        self.trash = trash
    }

    public static func isRemote(_ source: String) -> Bool {
        let lowercased = source.lowercased()
        return lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://")
    }

    public func prepare(
        source: String,
        progress: @escaping @Sendable (ImagePreparationProgress) -> Void
    ) async throws -> PreparedImage {
        var temporaryDirectory: URL?
        var keptDownload: KeptDownload?
        var trashReuse: TrashReuse?
        var checksumVerified = false
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
                let sidecar = await ChecksumSidecar.fetch(for: remoteURL)

                if let reuse = await reusableTrashedDownload(for: source, remoteURL: remoteURL),
                   let trashedFile = reuse.download.availableFile {
                    try FileManager.default.copyItem(at: trashedFile, to: localURL)
                    // Offline, fall back to the checksum computed when the file was downloaded.
                    let expected = sidecar.hash ?? (sidecar == .unreachable ? reuse.download.sha256 : nil)
                    if let expected {
                        if try ImageSupport.calculateSHA256(for: localURL) == expected {
                            trashReuse = reuse
                            checksumVerified = sidecar.hash != nil
                        } else {
                            // Damaged or outdated copy in the Trash: download again instead.
                            try FileManager.default.removeItem(at: localURL)
                        }
                    } else {
                        trashReuse = reuse
                    }
                }

                if trashReuse == nil {
                    let remote = try await ImageDownloader.download(from: remoteURL, to: localURL) { completed, total in
                        progress(ImagePreparationProgress(step: .download, fraction: Double(completed) / Double(total), processedBytes: completed))
                    }
                    let sha256 = try ImageSupport.calculateSHA256(for: localURL)
                    if let expected = sidecar.hash {
                        guard sha256 == expected else {
                            throw FlashError.invalidImage(
                                "Checksum mismatch for \(remoteURL.lastPathComponent): expected \(expected), got \(sha256)"
                            )
                        }
                        checksumVerified = true
                    }
                    if trashStore != nil {
                        keptDownload = KeptDownload(file: localURL, sourceURL: source, remote: remote, sha256: sha256)
                    }
                }
                sourceLocation = source
            } else {
                localURL = URL(fileURLWithPath: source)
                guard FileManager.default.fileExists(atPath: localURL.path) else {
                    throw FlashError.imageNotFound(localURL.path)
                }
                try ImageSupport.validateImageName(localURL.lastPathComponent)
                if let expected = ChecksumSidecar.read(forLocalFile: localURL).hash {
                    let sha256 = try ImageSupport.calculateSHA256(for: localURL)
                    guard sha256 == expected else {
                        throw FlashError.invalidImage(
                            "Checksum mismatch for \(localURL.lastPathComponent): expected \(expected), got \(sha256)"
                        )
                    }
                    checksumVerified = true
                }
                sourceLocation = localURL.path
            }

            if ImageSupport.isCompressed(localURL) {
                let directory = try temporaryDirectory ?? Self.makeTemporaryDirectory()
                temporaryDirectory = directory
                let decompressedURL = directory.appendingPathComponent(localURL.deletingPathExtension().lastPathComponent)
                try Self.decompressXZ(from: localURL, to: decompressedURL) { consumed, total, produced in
                    progress(ImagePreparationProgress(step: .decompress, fraction: Double(consumed) / Double(total), processedBytes: produced))
                }
                if Self.isRemote(source) && keptDownload == nil {
                    try? FileManager.default.removeItem(at: localURL)
                }
                localURL = decompressedURL
            }

            var image = try ImageSupport.validateImage(at: localURL.path)
            if sourceLocation != image.url.path {
                image.sourceLocation = sourceLocation
            }
            return PreparedImage(
                image: image,
                temporaryDirectory: temporaryDirectory,
                keptDownload: keptDownload,
                trashReuse: trashReuse,
                checksumVerified: checksumVerified
            )
        } catch {
            if let temporaryDirectory {
                try? FileManager.default.removeItem(at: temporaryDirectory)
            }
            throw error
        }
    }

    /// Moves a fresh download to the Trash (and remembers it), then removes all other temporary files.
    @discardableResult
    public func finish(_ prepared: PreparedImage) -> ImageCleanupResult {
        guard prepared.hasTemporaryFiles else {
            return .nothingToDo
        }
        defer { prepared.cleanup() }

        guard let kept = prepared.keptDownload, let trashStore else {
            return .removedTemporaryFiles
        }
        do {
            let size = (try FileManager.default.attributesOfItem(atPath: kept.file.path)[.size] as? NSNumber)?.int64Value ?? 0
            let trashed = try trash.moveToTrash(kept.file)
            try trashStore.record(
                TrashedDownload(
                    sourceURL: kept.sourceURL,
                    trashPath: trashed.path,
                    size: size,
                    remote: kept.remote,
                    downloadedAt: Date(),
                    sha256: kept.sha256
                )
            )
            return .movedDownloadToTrash(trashed)
        } catch {
            return .trashFailed(error.localizedDescription)
        }
    }

    /// The earlier download in the Trash, if it is still there and the server still serves the same file.
    /// If the server is not reachable, the trashed copy is used without that check.
    private func reusableTrashedDownload(for source: String, remoteURL: URL) async -> TrashReuse? {
        guard let entry = trashStore?.entry(for: source), entry.availableFile != nil else {
            return nil
        }
        guard let current = await RemoteFileInfo.fetch(from: remoteURL) else {
            return TrashReuse(download: entry, verifiedWithServer: false)
        }
        return entry.matches(current) ? TrashReuse(download: entry, verifiedWithServer: true) : nil
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
        progress: (_ consumedBytes: Int64, _ totalBytes: Int64, _ producedBytes: Int64) -> Void
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
        var produced: Int64 = 0
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
                    progress(consumed, totalSize, produced)
                }
            }

            stream.pointee.dst_ptr = destinationBuffer
            stream.pointee.dst_size = bufferSize
            let flags = reachedEndOfInput ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            let status = compression_stream_process(stream, flags)

            let chunkSize = bufferSize - stream.pointee.dst_size
            if chunkSize > 0 {
                try output.write(contentsOf: Data(bytes: destinationBuffer, count: chunkSize))
                produced += Int64(chunkSize)
            }

            switch status {
            case COMPRESSION_STATUS_END:
                progress(totalSize, totalSize, produced)
                return
            case COMPRESSION_STATUS_OK:
                if reachedEndOfInput && chunkSize == 0 {
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
    private var continuation: CheckedContinuation<RemoteFileInfo, Error>?
    private var finishError: Error?
    private var remote = RemoteFileInfo()

    private init(destination: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    static func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> RemoteFileInfo {
        let downloader = ImageDownloader(destination: destination, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: downloader, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RemoteFileInfo, Error>) in
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
        if let response = downloadTask.response as? HTTPURLResponse {
            remote = RemoteFileInfo(response: response)
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
            continuation?.resume(returning: remote)
        }
        continuation = nil
    }
}
