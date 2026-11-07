import Darwin
import Foundation

/// HTTP validators of a remote image, used to tell whether a copy in the Trash is still current.
public struct RemoteFileInfo: Codable, Equatable, Sendable {
    public var size: Int64?
    public var lastModified: String?
    public var etag: String?

    public init(size: Int64? = nil, lastModified: String? = nil, etag: String? = nil) {
        self.size = size
        self.lastModified = lastModified
        self.etag = etag
    }

    init(response: HTTPURLResponse) {
        let length = response.expectedContentLength
        size = length >= 0 ? length : nil
        lastModified = response.value(forHTTPHeaderField: "Last-Modified")
        etag = response.value(forHTTPHeaderField: "ETag")
    }

    /// Asks the server for the current validators with a HEAD request. Returns nil if the server is not reachable.
    static func fetch(from url: URL, timeout: TimeInterval = 5) async -> RemoteFileInfo? {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "HEAD"
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
            return nil
        }
        return RemoteFileInfo(response: http)
    }
}

/// A downloaded remote image that was moved to the user's Trash instead of being deleted.
public struct TrashedDownload: Codable, Equatable, Sendable {
    public var sourceURL: String
    public var trashPath: String
    public var size: Int64
    public var remote: RemoteFileInfo
    public var downloadedAt: Date
    /// SHA-256 of the file at download time.
    public var sha256: String?

    public init(
        sourceURL: String,
        trashPath: String,
        size: Int64,
        remote: RemoteFileInfo,
        downloadedAt: Date,
        sha256: String? = nil
    ) {
        self.sourceURL = sourceURL
        self.trashPath = trashPath
        self.size = size
        self.remote = remote
        self.downloadedAt = downloadedAt
        self.sha256 = sha256
    }

    /// True if the server still serves the same file. Prefers ETag, then Last-Modified, and always checks the size.
    public func matches(_ current: RemoteFileInfo) -> Bool {
        if let currentSize = current.size, currentSize != size {
            return false
        }
        if let etag = remote.etag, let currentETag = current.etag {
            return etag == currentETag
        }
        if let lastModified = remote.lastModified, let currentLastModified = current.lastModified {
            return lastModified == currentLastModified
        }
        return false
    }

    /// The trashed file, if it is still in the Trash with the expected size.
    public var availableFile: URL? {
        let url = URL(fileURLWithPath: trashPath)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attributes[.size] as? NSNumber)?.int64Value == size
        else {
            return nil
        }
        return url
    }
}

/// Moves files to the Trash of the user who started the tool, also when it runs via `sudo`.
public struct DownloadTrash: Sendable {
    private let move: @Sendable (URL) throws -> URL

    public init(move: @escaping @Sendable (URL) throws -> URL) {
        self.move = move
    }

    /// Moves `url` to the Trash and returns its new location.
    public func moveToTrash(_ url: URL) throws -> URL {
        try move(url)
    }

    public static let userTrash = DownloadTrash { url in
        try UserTrash.move(url)
    }
}

enum UserTrash {
    static func move(
        _ url: URL,
        env: [String: String] = ProcessInfo.processInfo.environment,
        effectiveUserID: uid_t = geteuid()
    ) throws -> URL {
        // Under sudo, FileManager.trashItem would use root's Trash. Move into the invoking user's Trash instead.
        if effectiveUserID == 0,
           let uid = env["SUDO_UID"].flatMap({ uid_t($0) }),
           let gid = env["SUDO_GID"].flatMap({ gid_t($0) }) {
            let home = try ConfigPathResolver.resolveUserHome(env: env, effectiveUserID: effectiveUserID)
            let trashDirectory = home.appendingPathComponent(".Trash", isDirectory: true)
            let destination = uniqueDestination(for: url.lastPathComponent, in: trashDirectory)
            try FileManager.default.moveItem(at: url, to: destination)
            _ = chown(destination.path, uid, gid)
            return destination
        }

        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return (result as URL?) ?? url
    }

    /// `name.img.xz`, then `name 2.img.xz`, `name 3.img.xz`, … like Finder does.
    static func uniqueDestination(for fileName: String, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent(fileName)
        let parts = fileName.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let base = String(parts[0])
        let suffix = parts.count > 1 ? ".\(parts[1])" : ""
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(counter)\(suffix)")
            counter += 1
        }
        return candidate
    }
}
