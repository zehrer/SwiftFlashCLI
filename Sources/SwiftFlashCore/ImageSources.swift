import Foundation

/// A named server directory with images, e.g. `redox` → `http://homenodellm:8080/sdcard/`.
/// Images on it can be referenced as `redox:<family>` (newest build) or browsed with `redox:`.
public struct ImageSource: Codable, Equatable, Sendable {
    public var name: String
    public var url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }

    /// The directory URL, always ending in `/` so relative links resolve inside it.
    public var directoryURL: URL? {
        URL(string: url.hasSuffix("/") ? url : url + "/")
    }

    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}

/// One image file offered by a source.
public struct RemoteImage: Equatable, Sendable {
    public var fileName: String
    public var url: URL
    /// File name without version and extension, e.g. `redox-rpi-t18-direct`.
    public var family: String
    public var version: String?
    /// Build date from `index.json` or the server's `Last-Modified`, used to find the newest build.
    public var date: Date?

    public init(fileName: String, url: URL, family: String, version: String?, date: Date?) {
        self.fileName = fileName
        self.url = url
        self.family = family
        self.version = version
        self.date = date
    }
}

/// All builds of one image family, newest first.
public struct RemoteImageFamily: Equatable, Sendable {
    public var name: String
    public var builds: [RemoteImage]

    public var newest: RemoteImage {
        builds[0]
    }
}

/// A `source:family` reference as typed by the user. `family` is empty for `source:` (browse).
public struct ImageSourceReference: Equatable, Sendable {
    public var sourceName: String
    public var family: String

    /// Parses `name:rest` when `name` is a configured source. Everything else (paths, URLs) returns nil.
    public static func parse(_ text: String, sources: [ImageSource]) -> ImageSourceReference? {
        guard !ImagePreparer.isRemote(text), let colon = text.firstIndex(of: ":") else {
            return nil
        }
        let name = String(text[..<colon])
        guard sources.contains(where: { $0.name == name }) else {
            return nil
        }
        return ImageSourceReference(sourceName: name, family: String(text[text.index(after: colon)...]))
    }
}

public enum RemoteImageNaming {
    private static let versionPatterns = [
        // git describe style: -v0.4.0-dev-36-g1107e5f7+x95e1
        #"-v\d+\.\d+.*$"#,
        // date style: -20261107b, -20261107-2
        #"-\d{8}[A-Za-z0-9.-]*$"#,
    ]

    /// Splits `redox-rpi-t18-direct-v0.4.0-dev-36-g1107e5f7+x95e1.img.xz` into family and version.
    public static func split(fileName: String) -> (family: String, version: String?) {
        var base = URL(fileURLWithPath: fileName)
        if ImageSupport.isCompressed(base) {
            base = base.deletingPathExtension()
        }
        let name = base.deletingPathExtension().lastPathComponent
        for pattern in versionPatterns {
            if let range = name.range(of: pattern, options: .regularExpression), range.lowerBound > name.startIndex {
                return (String(name[..<range.lowerBound]), String(name[range].dropFirst()))
            }
        }
        return (name, nil)
    }

    /// Groups images into families, each sorted newest first (by date, then by file name).
    public static func families(from images: [RemoteImage]) -> [RemoteImageFamily] {
        Dictionary(grouping: images, by: \.family)
            .map { name, builds in
                RemoteImageFamily(name: name, builds: builds.sorted(by: isNewer))
            }
            .sorted { $0.name < $1.name }
    }

    static func isNewer(_ lhs: RemoteImage, _ rhs: RemoteImage) -> Bool {
        switch (lhs.date, rhs.date) {
        case let (left?, right?) where left != right:
            return left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.fileName.compare(rhs.fileName, options: .numeric) == .orderedDescending
        }
    }

    /// Finds the family for a user query: exact name, else the one family whose name ends with `-query`
    /// or contains `query`. Throws if nothing or more than one family matches.
    public static func family(matching query: String, in families: [RemoteImageFamily]) throws -> RemoteImageFamily {
        if let exact = families.first(where: { $0.name == query }) {
            return exact
        }
        for predicate in [{ (name: String) in name.hasSuffix("-" + query) }, { $0.contains(query) }] {
            let matches = families.filter { predicate($0.name) }
            if matches.count == 1 {
                return matches[0]
            }
            if matches.count > 1 {
                throw FlashError.usage(
                    "'\(query)' matches several images: \(matches.map(\.name).joined(separator: ", "))"
                )
            }
        }
        throw FlashError.usage("No image family matches '\(query)'")
    }
}

/// Reads the image list of a source: `index.json` if the server has one, otherwise the HTML directory listing.
public final class ImageSourceBrowser: Sendable {
    public init() {}

    public func images(in source: ImageSource) async throws -> [RemoteImage] {
        guard let directory = source.directoryURL else {
            throw FlashError.usage("Invalid source URL: \(source.url)")
        }
        if let data = try await fetch(directory.appendingPathComponent("index.json")),
           let images = Self.parseIndex(data, base: directory) {
            return images
        }
        guard let data = try await fetch(directory) else {
            throw FlashError.ioFailed("Could not list \(directory.absoluteString)")
        }
        let images = Self.parseDirectoryListing(String(decoding: data, as: UTF8.self), base: directory)
        return await withLastModifiedDates(images)
    }

    public func families(in source: ImageSource) async throws -> [RemoteImageFamily] {
        RemoteImageNaming.families(from: try await images(in: source))
    }

    /// Image links (supported extensions only) in an HTML directory listing, as produced by `python -m http.server`.
    static func parseDirectoryListing(_ html: String, base: URL) -> [RemoteImage] {
        let pattern = #"href\s*=\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        var seen = Set<String>()
        return regex.matches(in: html, range: range).compactMap { match in
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let url = URL(string: String(html[hrefRange]), relativeTo: base)?.absoluteURL
            else {
                return nil
            }
            let fileName = url.lastPathComponent
            guard url.absoluteString.hasPrefix(base.absoluteString),
                  (try? ImageSupport.validateImageName(fileName)) != nil,
                  seen.insert(fileName).inserted
            else {
                return nil
            }
            let (family, version) = RemoteImageNaming.split(fileName: fileName)
            return RemoteImage(fileName: fileName, url: url, family: family, version: version, date: nil)
        }
    }

    /// Optional `index.json` written by a build server; see `docs/image-sources.md`.
    static func parseIndex(_ data: Data, base: URL) -> [RemoteImage]? {
        struct Index: Decodable {
            struct Entry: Decodable {
                var file: String
                var family: String?
                var version: String?
                var date: Date?
            }
            var images: [Entry]
        }
        guard let index = try? JSONCoding.decoder.decode(Index.self, from: data) else {
            return nil
        }
        return index.images.compactMap { entry in
            guard let url = URL(string: entry.file, relativeTo: base)?.absoluteURL,
                  (try? ImageSupport.validateImageName(url.lastPathComponent)) != nil
            else {
                return nil
            }
            let derived = RemoteImageNaming.split(fileName: url.lastPathComponent)
            return RemoteImage(
                fileName: url.lastPathComponent,
                url: url,
                family: entry.family ?? derived.family,
                version: entry.version ?? derived.version,
                date: entry.date
            )
        }
    }

    private func fetch(_ url: URL) async throws -> Data? {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: 10))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        return data
    }

    /// Directory listings carry no dates, so ask the server for each file's `Last-Modified`.
    private func withLastModifiedDates(_ images: [RemoteImage]) async -> [RemoteImage] {
        await withTaskGroup(of: (Int, Date?).self) { group in
            for (index, image) in images.enumerated() {
                group.addTask {
                    let info = await RemoteFileInfo.fetch(from: image.url)
                    return (index, info?.lastModified.flatMap(Self.parseHTTPDate))
                }
            }
            var result = images
            for await (index, date) in group {
                result[index].date = date
            }
            return result
        }
    }

    static func parseHTTPDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: text)
    }
}
