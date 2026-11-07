import Darwin
import Foundation

public final class AppConfigStore {
    public let configURL: URL
    /// Owner to give the config directory and file after saving, e.g. the user who ran `sudo`.
    private let owner: ConfigFileOwner?
    private var config: AppConfig

    public init(configURL: URL? = nil, owner: ConfigFileOwner? = ConfigFileOwner.sudoInvoker()) throws {
        self.configURL = try configURL ?? ConfigPathResolver.defaultConfigURL()
        self.owner = owner
        self.config = try Self.loadConfig(from: self.configURL)
    }

    public func currentConfig() -> AppConfig {
        config
    }

    public func update(_ mutate: (inout AppConfig) -> Void) throws {
        mutate(&config)
        try save()
    }

    public func save() throws {
        let directory = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONCoding.encoder.encode(config)
        do {
            try data.write(to: configURL, options: .atomic)
        } catch CocoaError.fileWriteNoPermission {
            throw FlashError.persistenceFailed(
                "No permission to write \(configURL.path). It is probably owned by root from an older version; "
                    + "run `sudo swiftflash history` once to fix the ownership."
            )
        }
        if let owner {
            // Under sudo the file is written by root; hand it back so later commands without sudo can update it.
            _ = chown(directory.path, owner.uid, owner.gid)
            _ = chown(configURL.path, owner.uid, owner.gid)
        }
    }

    private static func loadConfig(from url: URL) throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AppConfig()
        }
        let data = try Data(contentsOf: url)
        return try JSONCoding.decoder.decode(AppConfig.self, from: data)
    }
}

public struct ConfigFileOwner: Equatable, Sendable {
    public var uid: uid_t
    public var gid: gid_t

    public init(uid: uid_t, gid: gid_t) {
        self.uid = uid
        self.gid = gid
    }

    /// The user who started the tool via `sudo`, or nil when not running as root through sudo.
    public static func sudoInvoker(
        env: [String: String] = ProcessInfo.processInfo.environment,
        effectiveUserID: uid_t = geteuid()
    ) -> ConfigFileOwner? {
        guard effectiveUserID == 0,
              let uid = env["SUDO_UID"].flatMap({ uid_t($0) }),
              let gid = env["SUDO_GID"].flatMap({ gid_t($0) }),
              uid != 0
        else {
            return nil
        }
        return ConfigFileOwner(uid: uid, gid: gid)
    }
}

public enum ConfigPathResolver {
    public static func defaultConfigURL(
        env: [String: String] = ProcessInfo.processInfo.environment,
        effectiveUserID: uid_t = geteuid()
    ) throws -> URL {
        let baseHome = try resolveUserHome(env: env, effectiveUserID: effectiveUserID)
        return baseHome
            .appendingPathComponent(".swiftflash", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    static func resolveUserHome(
        env: [String: String] = ProcessInfo.processInfo.environment,
        effectiveUserID: uid_t = geteuid()
    ) throws -> URL {
        if effectiveUserID == 0, let sudoUser = env["SUDO_USER"], !sudoUser.isEmpty {
            if let pwd = getpwnam(sudoUser) {
                let home = String(cString: pwd.pointee.pw_dir)
                return URL(fileURLWithPath: home, isDirectory: true)
            }
        }

        if let home = env["HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }
}

public final class ImageCatalogStore {
    private let configStore: AppConfigStore

    public init(configStore: AppConfigStore) {
        self.configStore = configStore
    }

    public func allImages() -> [RememberedImage] {
        configStore.currentConfig().rememberedImages.sorted { $0.lastUsed > $1.lastUsed }
    }

    public func remember(image: ImageDescriptor) throws {
        try configStore.update { config in
            let now = Date()
            if let index = config.rememberedImages.firstIndex(where: { $0.path == image.sourcePath }) {
                config.rememberedImages[index].displayName = image.name
                config.rememberedImages[index].size = image.size
                config.rememberedImages[index].sha256 = image.checksum
                config.rememberedImages[index].lastUsed = now
            } else {
                config.rememberedImages.insert(
                    RememberedImage(
                        path: image.sourcePath,
                        displayName: image.name,
                        size: image.size,
                        sha256: image.checksum,
                        firstSeen: now,
                        lastUsed: now
                    ),
                    at: 0
                )
            }
            config.rememberedImages.sort { $0.lastUsed > $1.lastUsed }
        }
    }

    /// Removes remembered images whose path or display name matches `query`.
    /// Returns the number of removed entries.
    @discardableResult
    public func remove(matching query: String) throws -> Int {
        var removed = 0
        try configStore.update { config in
            let before = config.rememberedImages.count
            config.rememberedImages.removeAll { image in
                image.path == query || image.displayName.caseInsensitiveCompare(query) == .orderedSame
            }
            removed = before - config.rememberedImages.count
        }
        return removed
    }

    public func clear() throws {
        try configStore.update { config in
            config.rememberedImages.removeAll()
        }
    }
}

public final class ImageSourceStore {
    private let configStore: AppConfigStore

    public init(configStore: AppConfigStore) {
        self.configStore = configStore
    }

    public func allSources() -> [ImageSource] {
        configStore.currentConfig().imageSources.sorted { $0.name < $1.name }
    }

    public func source(named name: String) -> ImageSource? {
        configStore.currentConfig().imageSources.first { $0.name == name }
    }

    /// Adds a source or replaces the URL of an existing one with the same name.
    public func add(_ source: ImageSource) throws {
        guard ImageSource.isValidName(source.name) else {
            throw FlashError.usage("Source names may only contain letters, digits, '-' and '_': \(source.name)")
        }
        guard ImagePreparer.isRemote(source.url), source.directoryURL != nil else {
            throw FlashError.usage("Source URL must be an http(s) directory URL: \(source.url)")
        }
        try configStore.update { config in
            config.imageSources.removeAll { $0.name == source.name }
            config.imageSources.append(source)
        }
    }

    @discardableResult
    public func remove(named name: String) throws -> Bool {
        var removed = false
        try configStore.update { config in
            let before = config.imageSources.count
            config.imageSources.removeAll { $0.name == name }
            removed = config.imageSources.count != before
        }
        return removed
    }
}

/// Remembers which downloaded remote images were moved to the Trash, so they can be reused.
public final class TrashedDownloadStore {
    private let configStore: AppConfigStore

    public init(configStore: AppConfigStore) {
        self.configStore = configStore
    }

    public func entry(for sourceURL: String) -> TrashedDownload? {
        configStore.currentConfig().trashedDownloads.first { $0.sourceURL == sourceURL }
    }

    /// Stores `download`, replacing an older entry for the same URL.
    public func record(_ download: TrashedDownload) throws {
        try configStore.update { config in
            config.trashedDownloads.removeAll { $0.sourceURL == download.sourceURL }
            config.trashedDownloads.append(download)
        }
    }

    public func remove(sourceURL: String) throws {
        try configStore.update { config in
            config.trashedDownloads.removeAll { $0.sourceURL == sourceURL }
        }
    }
}

public final class DeviceInventoryStore {
    private let configStore: AppConfigStore

    public init(configStore: AppConfigStore) {
        self.configStore = configStore
    }

    public func allDevices() -> [KnownPhysicalDevice] {
        configStore.currentConfig().knownPhysicalDevices.sorted { $0.lastSeen > $1.lastSeen }
    }

    public func allMediaTypes() -> [MediaTypeDefinition] {
        configStore.currentConfig().mediaTypes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func findMediaType(named query: String) -> MediaTypeDefinition? {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return nil
        }
        return allMediaTypes().first { $0.name.lowercased() == normalizedQuery }
    }

    public func findDevice(matching query: String) -> KnownPhysicalDevice? {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return nil
        }

        return allDevices().first { device in
            device.deviceUUID.lowercased() == normalizedQuery
                || device.customName?.lowercased() == normalizedQuery
                || device.displayName.lowercased() == normalizedQuery
        }
    }

    public func addMediaType(name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FlashError.usage("Media type name must not be empty")
        }

        try configStore.update { config in
            let exists = config.mediaTypes.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
            guard !exists else {
                return
            }
            config.mediaTypes.append(
                MediaTypeDefinition(name: trimmed, isPreconfigured: false, createdAt: Date())
            )
            config.mediaTypes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    public func upsert(deviceUUID: String, candidate: DiskCandidate) throws {
        try configStore.update { config in
            let now = Date()
            if let index = config.knownPhysicalDevices.firstIndex(where: { $0.deviceUUID == deviceUUID }) {
                config.knownPhysicalDevices[index].size = candidate.size
                config.knownPhysicalDevices[index].lastSeen = now
            } else {
                config.knownPhysicalDevices.append(
                    KnownPhysicalDevice(
                        deviceUUID: deviceUUID,
                        customName: nil,
                        size: candidate.size,
                        firstSeen: now,
                        lastSeen: now
                    )
                )
            }
        }
    }

    public func setCustomName(id: String, name: String?) throws {
        try configStore.update { config in
            guard let index = config.knownPhysicalDevices.firstIndex(where: { $0.deviceUUID == id }) else {
                return
            }
            config.knownPhysicalDevices[index].customName = name
        }
    }

    public func setMediaType(id: String, mediaTypeName: String?) throws {
        let normalizedMediaType = mediaTypeName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedMediaType, !normalizedMediaType.isEmpty {
            guard findMediaType(named: normalizedMediaType) != nil else {
                throw FlashError.usage("Unknown media type: \(normalizedMediaType)")
            }
        }

        try configStore.update { config in
            guard let index = config.knownPhysicalDevices.firstIndex(where: { $0.deviceUUID == id }) else {
                return
            }
            config.knownPhysicalDevices[index].mediaTypeName = normalizedMediaType?.isEmpty == true ? nil : normalizedMediaType
        }
    }
}

public final class FlashHistoryStore {
    private let configStore: AppConfigStore

    public init(configStore: AppConfigStore) {
        self.configStore = configStore
    }

    public func allHistory() -> [FlashHistoryEntry] {
        configStore.currentConfig().flashHistory.sorted { $0.startedAt > $1.startedAt }
    }

    public func add(_ entry: FlashHistoryEntry) throws {
        try configStore.update { config in
            config.flashHistory.insert(entry, at: 0)
        }
    }

    public func clear() throws {
        try configStore.update { config in
            config.flashHistory.removeAll()
        }
    }

    public func upsertFlashMedia(_ media: KnownFlashMedia) throws {
        try configStore.update { config in
            if let index = config.knownFlashMedia.firstIndex(where: { $0.flashUUID == media.flashUUID }) {
                config.knownFlashMedia[index] = media
            } else {
                config.knownFlashMedia.append(media)
            }
        }
    }
}
