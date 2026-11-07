import Foundation

/// A `<image>.sha256` file next to an image, as published by build servers
/// (`sha256sum` format: `<64 hex chars>  <file name>`, or just the hash).
public enum ChecksumSidecar: Equatable, Sendable {
    case found(String)
    /// The server answered, but there is no (valid) `.sha256` file.
    case missing
    /// The server could not be reached.
    case unreachable

    public var hash: String? {
        if case .found(let hash) = self {
            return hash
        }
        return nil
    }

    public static func sidecarURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".sha256")
    }

    /// Extracts the SHA-256 from `sha256sum` output. Returns nil if the text does not start with a valid hash.
    public static func parse(_ text: String) -> String? {
        guard let token = text.split(whereSeparator: \.isWhitespace).first else {
            return nil
        }
        let hash = token.lowercased()
        guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else {
            return nil
        }
        return hash
    }

    static func fetch(for remoteURL: URL, timeout: TimeInterval = 10) async -> ChecksumSidecar {
        let request = URLRequest(url: sidecarURL(for: remoteURL), timeoutInterval: timeout)
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse
        else {
            return .unreachable
        }
        guard (200..<300).contains(http.statusCode),
              let hash = parse(String(decoding: data.prefix(4096), as: UTF8.self))
        else {
            return .missing
        }
        return .found(hash)
    }

    static func read(forLocalFile url: URL) -> ChecksumSidecar {
        guard let data = FileManager.default.contents(atPath: sidecarURL(for: url).path) else {
            return .missing
        }
        return parse(String(decoding: data.prefix(4096), as: UTF8.self)).map(ChecksumSidecar.found) ?? .missing
    }
}
