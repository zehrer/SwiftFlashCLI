import CryptoKit
import Foundation

public struct AppConfig: Codable, Equatable, Sendable {
    public var rememberedImages: [RememberedImage]
    public var knownPhysicalDevices: [KnownPhysicalDevice]
    public var knownFlashMedia: [KnownFlashMedia]
    public var flashHistory: [FlashHistoryEntry]

    public init(
        rememberedImages: [RememberedImage] = [],
        knownPhysicalDevices: [KnownPhysicalDevice] = [],
        knownFlashMedia: [KnownFlashMedia] = [],
        flashHistory: [FlashHistoryEntry] = []
    ) {
        self.rememberedImages = rememberedImages
        self.knownPhysicalDevices = knownPhysicalDevices
        self.knownFlashMedia = knownFlashMedia
        self.flashHistory = flashHistory
    }
}

public struct RememberedImage: Codable, Equatable, Sendable {
    public var path: String
    public var displayName: String
    public var size: Int64
    public var sha256: String?
    public var firstSeen: Date
    public var lastUsed: Date

    public init(
        path: String,
        displayName: String,
        size: Int64,
        sha256: String? = nil,
        firstSeen: Date,
        lastUsed: Date
    ) {
        self.path = path
        self.displayName = displayName
        self.size = size
        self.sha256 = sha256
        self.firstSeen = firstSeen
        self.lastUsed = lastUsed
    }
}

public struct KnownPhysicalDevice: Codable, Equatable, Sendable {
    public var deviceUUID: String
    public var customName: String?
    public var size: Int64
    public var firstSeen: Date
    public var lastSeen: Date
    public var userDefinedFields: [String: String]

    public init(
        deviceUUID: String,
        customName: String? = nil,
        vendor: String? = nil,
        model: String? = nil,
        protocolName: String? = nil,
        size: Int64,
        firstSeen: Date,
        lastSeen: Date,
        userDefinedFields: [String: String] = [:]
    ) {
        self.deviceUUID = deviceUUID
        self.customName = customName
        self.size = size
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.userDefinedFields = userDefinedFields
    }

    public var displayName: String {
        customName ?? deviceUUID
    }

    private enum CodingKeys: String, CodingKey {
        case deviceUUID
        case physicalDeviceID
        case customName
        case size
        case firstSeen
        case lastSeen
        case userDefinedFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceUUID = try container.decodeIfPresent(String.self, forKey: .deviceUUID)
            ?? container.decode(String.self, forKey: .physicalDeviceID)
        customName = try container.decodeIfPresent(String.self, forKey: .customName)
        size = try container.decode(Int64.self, forKey: .size)
        firstSeen = try container.decode(Date.self, forKey: .firstSeen)
        lastSeen = try container.decode(Date.self, forKey: .lastSeen)
        userDefinedFields = try container.decodeIfPresent([String: String].self, forKey: .userDefinedFields) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceUUID, forKey: .deviceUUID)
        try container.encodeIfPresent(customName, forKey: .customName)
        try container.encode(size, forKey: .size)
        try container.encode(firstSeen, forKey: .firstSeen)
        try container.encode(lastSeen, forKey: .lastSeen)
        try container.encode(userDefinedFields, forKey: .userDefinedFields)
    }
}

public struct KnownFlashMedia: Codable, Equatable, Sendable {
    public var flashUUID: UUID
    public var lastImagePath: String
    public var lastImageName: String
    public var deviceUUID: String
    public var flashedAt: Date
    public var lastSeen: Date

    public init(
        flashUUID: UUID,
        lastImagePath: String,
        lastImageName: String,
        deviceUUID: String,
        flashedAt: Date,
        lastSeen: Date
    ) {
        self.flashUUID = flashUUID
        self.lastImagePath = lastImagePath
        self.lastImageName = lastImageName
        self.deviceUUID = deviceUUID
        self.flashedAt = flashedAt
        self.lastSeen = lastSeen
    }

    private enum CodingKeys: String, CodingKey {
        case flashUUID
        case lastImagePath
        case lastImageName
        case deviceUUID
        case lastPhysicalDeviceID
        case flashedAt
        case lastSeen
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        flashUUID = try container.decode(UUID.self, forKey: .flashUUID)
        lastImagePath = try container.decode(String.self, forKey: .lastImagePath)
        lastImageName = try container.decode(String.self, forKey: .lastImageName)
        deviceUUID = try container.decodeIfPresent(String.self, forKey: .deviceUUID)
            ?? container.decode(String.self, forKey: .lastPhysicalDeviceID)
        flashedAt = try container.decode(Date.self, forKey: .flashedAt)
        lastSeen = try container.decode(Date.self, forKey: .lastSeen)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(flashUUID, forKey: .flashUUID)
        try container.encode(lastImagePath, forKey: .lastImagePath)
        try container.encode(lastImageName, forKey: .lastImageName)
        try container.encode(deviceUUID, forKey: .deviceUUID)
        try container.encode(flashedAt, forKey: .flashedAt)
        try container.encode(lastSeen, forKey: .lastSeen)
    }
}

public struct FlashHistoryEntry: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var finishedAt: Date
    public var imagePath: String
    public var imageName: String
    public var deviceUUID: String
    public var previousFlashUUID: UUID?
    public var newFlashUUID: UUID?
    public var uuidWriteSucceeded: Bool
    public var result: String

    public init(
        startedAt: Date,
        finishedAt: Date,
        imagePath: String,
        imageName: String,
        deviceUUID: String,
        previousFlashUUID: UUID?,
        newFlashUUID: UUID?,
        uuidWriteSucceeded: Bool,
        result: String
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.imagePath = imagePath
        self.imageName = imageName
        self.deviceUUID = deviceUUID
        self.previousFlashUUID = previousFlashUUID
        self.newFlashUUID = newFlashUUID
        self.uuidWriteSucceeded = uuidWriteSucceeded
        self.result = result
    }

    private enum CodingKeys: String, CodingKey {
        case startedAt
        case finishedAt
        case imagePath
        case imageName
        case deviceUUID
        case physicalDeviceID
        case previousFlashUUID
        case newFlashUUID
        case uuidWriteSucceeded
        case result
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        finishedAt = try container.decode(Date.self, forKey: .finishedAt)
        imagePath = try container.decode(String.self, forKey: .imagePath)
        imageName = try container.decode(String.self, forKey: .imageName)
        deviceUUID = try container.decodeIfPresent(String.self, forKey: .deviceUUID)
            ?? container.decode(String.self, forKey: .physicalDeviceID)
        previousFlashUUID = try container.decodeIfPresent(UUID.self, forKey: .previousFlashUUID)
        newFlashUUID = try container.decodeIfPresent(UUID.self, forKey: .newFlashUUID)
        uuidWriteSucceeded = try container.decode(Bool.self, forKey: .uuidWriteSucceeded)
        result = try container.decode(String.self, forKey: .result)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(finishedAt, forKey: .finishedAt)
        try container.encode(imagePath, forKey: .imagePath)
        try container.encode(imageName, forKey: .imageName)
        try container.encode(deviceUUID, forKey: .deviceUUID)
        try container.encodeIfPresent(previousFlashUUID, forKey: .previousFlashUUID)
        try container.encodeIfPresent(newFlashUUID, forKey: .newFlashUUID)
        try container.encode(uuidWriteSucceeded, forKey: .uuidWriteSucceeded)
        try container.encode(result, forKey: .result)
    }
}

public struct FlashUUIDMetadata: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var flashUUID: UUID?
    public var deviceUUID: String
    public var deviceName: String?
    public var imagePath: String
    public var imageName: String
    public var imageSHA256: String?
    public var flashedAt: Date

    public init(
        schemaVersion: Int = 1,
        flashUUID: UUID?,
        deviceUUID: String,
        deviceName: String?,
        imagePath: String,
        imageName: String,
        imageSHA256: String?,
        flashedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.flashUUID = flashUUID
        self.deviceUUID = deviceUUID
        self.deviceName = deviceName
        self.imagePath = imagePath
        self.imageName = imageName
        self.imageSHA256 = imageSHA256
        self.flashedAt = flashedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case flashUUID
        case deviceUUID
        case physicalDeviceID
        case deviceName
        case physicalDeviceName
        case imagePath
        case imageName
        case imageSHA256
        case flashedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        flashUUID = try container.decodeIfPresent(UUID.self, forKey: .flashUUID)
        deviceUUID = try container.decodeIfPresent(String.self, forKey: .deviceUUID)
            ?? container.decode(String.self, forKey: .physicalDeviceID)
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName)
            ?? container.decodeIfPresent(String.self, forKey: .physicalDeviceName)
        imagePath = try container.decode(String.self, forKey: .imagePath)
        imageName = try container.decode(String.self, forKey: .imageName)
        imageSHA256 = try container.decodeIfPresent(String.self, forKey: .imageSHA256)
        flashedAt = try container.decode(Date.self, forKey: .flashedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(flashUUID, forKey: .flashUUID)
        try container.encode(deviceUUID, forKey: .deviceUUID)
        try container.encodeIfPresent(deviceName, forKey: .deviceName)
        try container.encode(imagePath, forKey: .imagePath)
        try container.encode(imageName, forKey: .imageName)
        try container.encodeIfPresent(imageSHA256, forKey: .imageSHA256)
        try container.encode(flashedAt, forKey: .flashedAt)
    }
}

public enum DeviceIdentitySource: String, Equatable, Sendable {
    case file
    case trailer
    case created

    public var displayLabel: String {
        switch self {
        case .file:
            return "reused(.uuid)"
        case .trailer:
            return "reused(trailer)"
        case .created:
            return "created(.uuid)"
        }
    }
}

public struct ResolvedDeviceIdentity: Equatable, Sendable {
    public var metadata: FlashUUIDMetadata
    public var source: DeviceIdentitySource

    public init(metadata: FlashUUIDMetadata, source: DeviceIdentitySource) {
        self.metadata = metadata
        self.source = source
    }
}

public struct FlashCompletion: Equatable, Sendable {
    public var previousIdentity: ResolvedDeviceIdentity?
    public var metadata: FlashUUIDMetadata
    public var writeResult: MetadataWriteResult
    public var verified: Bool

    public init(
        previousIdentity: ResolvedDeviceIdentity?,
        metadata: FlashUUIDMetadata,
        writeResult: MetadataWriteResult,
        verified: Bool
    ) {
        self.previousIdentity = previousIdentity
        self.metadata = metadata
        self.writeResult = writeResult
        self.verified = verified
    }
}

public struct PartitionVolume: Equatable, Sendable {
    public var bsdName: String
    public var mountPoint: String?
    public var volumeName: String?
    public var volumeKind: String?
    public var isMountable: Bool
    public var isWritable: Bool

    public init(
        bsdName: String,
        mountPoint: String?,
        volumeName: String?,
        volumeKind: String?,
        isMountable: Bool,
        isWritable: Bool
    ) {
        self.bsdName = bsdName
        self.mountPoint = mountPoint
        self.volumeName = volumeName
        self.volumeKind = volumeKind
        self.isMountable = isMountable
        self.isWritable = isWritable
    }
}

public struct DiskCandidate: Equatable, Sendable {
    public var devicePath: String
    public var rawDevicePath: String
    public var bsdName: String
    public var physicalDeviceID: String
    public var name: String
    public var vendor: String?
    public var model: String?
    public var protocolName: String?
    public var serialNumber: String?
    public var size: Int64
    public var isInternal: Bool
    public var isRemovable: Bool
    public var isEjectable: Bool
    public var isWritable: Bool
    public var isWhole: Bool
    public var mediaUUID: String?
    public var mediaKind: String?
    public var partitions: [PartitionVolume]

    public init(
        devicePath: String,
        rawDevicePath: String,
        bsdName: String,
        physicalDeviceID: String,
        name: String,
        vendor: String?,
        model: String?,
        protocolName: String?,
        serialNumber: String?,
        size: Int64,
        isInternal: Bool,
        isRemovable: Bool,
        isEjectable: Bool,
        isWritable: Bool,
        isWhole: Bool,
        mediaUUID: String?,
        mediaKind: String?,
        partitions: [PartitionVolume]
    ) {
        self.devicePath = devicePath
        self.rawDevicePath = rawDevicePath
        self.bsdName = bsdName
        self.physicalDeviceID = physicalDeviceID
        self.name = name
        self.vendor = vendor
        self.model = model
        self.protocolName = protocolName
        self.serialNumber = serialNumber
        self.size = size
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isWritable = isWritable
        self.isWhole = isWhole
        self.mediaUUID = mediaUUID
        self.mediaKind = mediaKind
        self.partitions = partitions
    }

    public var displayName: String {
        name.isEmpty ? bsdName : name
    }

    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    public var isDiskImage: Bool {
        if let mediaKind, mediaKind.localizedCaseInsensitiveContains("disk image") {
            return true
        }
        if model?.localizedCaseInsensitiveContains("disk image") == true {
            return true
        }
        return name.localizedCaseInsensitiveContains("disk image")
    }
}

public struct RawDiskSnapshot: Equatable, Sendable {
    public var devicePath: String
    public var bsdName: String
    public var name: String
    public var vendor: String?
    public var model: String?
    public var protocolName: String?
    public var serialNumber: String?
    public var size: Int64
    public var isInternal: Bool
    public var isRemovable: Bool
    public var isEjectable: Bool
    public var isWritable: Bool
    public var isWhole: Bool
    public var mediaUUID: String?
    public var mediaKind: String?
    public var partitions: [PartitionVolume]

    public init(
        devicePath: String,
        bsdName: String,
        name: String,
        vendor: String? = nil,
        model: String? = nil,
        protocolName: String? = nil,
        serialNumber: String? = nil,
        size: Int64,
        isInternal: Bool,
        isRemovable: Bool,
        isEjectable: Bool,
        isWritable: Bool,
        isWhole: Bool,
        mediaUUID: String? = nil,
        mediaKind: String? = nil,
        partitions: [PartitionVolume] = []
    ) {
        self.devicePath = devicePath
        self.bsdName = bsdName
        self.name = name
        self.vendor = vendor
        self.model = model
        self.protocolName = protocolName
        self.serialNumber = serialNumber
        self.size = size
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isWritable = isWritable
        self.isWhole = isWhole
        self.mediaUUID = mediaUUID
        self.mediaKind = mediaKind
        self.partitions = partitions
    }
}

public struct ImageDescriptor: Equatable, Sendable {
    public var url: URL
    public var size: Int64
    public var checksum: String?

    public init(url: URL, size: Int64, checksum: String?) {
        self.url = url
        self.size = size
        self.checksum = checksum
    }

    public var name: String {
        url.lastPathComponent
    }
}

public enum PartitionScheme: String, Equatable, Sendable {
    case mbr = "MBR"
    case gpt = "GPT"
    case unknown = "Unknown"
}

public enum FlashCommand: Equatable, Sendable {
    case flash(imagePath: String?, devicePath: String?, skipConfirmation: Bool)
    case verify(imagePath: String?, devicePath: String?)
    case images
    case devicesConnected
    case devicesKnown
    case deviceName(id: String, name: String)
    case deviceClearName(id: String)
    case history
    case historyClear
    case help
}

public enum FlashError: LocalizedError, Equatable {
    case usage(String)
    case requiresRoot
    case imageNotFound(String)
    case invalidImage(String)
    case imageTooLarge(imageSize: Int64, deviceSize: Int64)
    case deviceNotFound(String)
    case noEligibleDevices
    case cancelled
    case unmountFailed(String)
    case mountFailed(String)
    case rawWriteFailed(String)
    case verificationFailed(String)
    case persistenceFailed(String)
    case ioFailed(String)

    public var errorDescription: String? {
        switch self {
        case .usage(let message):
            message
        case .requiresRoot:
            "Please run with sudo"
        case .imageNotFound(let path):
            "Image file not found: \(path)"
        case .invalidImage(let reason):
            reason
        case .imageTooLarge(let imageSize, let deviceSize):
            "Image is too large for the selected device (\(imageSize) > \(deviceSize))"
        case .deviceNotFound(let path):
            "Device not found or not eligible: \(path)"
        case .noEligibleDevices:
            "No external physical devices are available"
        case .cancelled:
            "Operation cancelled"
        case .unmountFailed(let reason):
            "Failed to unmount device: \(reason)"
        case .mountFailed(let reason):
            "Failed to mount volume: \(reason)"
        case .rawWriteFailed(let reason):
            "Flash write failed: \(reason)"
        case .verificationFailed(let reason):
            "Verification failed: \(reason)"
        case .persistenceFailed(let reason):
            "Failed to persist config: \(reason)"
        case .ioFailed(let reason):
            "I/O failure: \(reason)"
        }
    }
}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum Hashing {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct MetadataWriteResult: Equatable, Sendable {
    public var fileWritten: Bool
    public var trailerWritten: Bool

    public init(fileWritten: Bool, trailerWritten: Bool) {
        self.fileWritten = fileWritten
        self.trailerWritten = trailerWritten
    }

    public var anyWritten: Bool {
        fileWritten || trailerWritten
    }

    public var storageDescription: String {
        switch (fileWritten, trailerWritten) {
        case (true, true):
            return ".uuid file + trailer"
        case (true, false):
            return ".uuid file"
        case (false, true):
            return "trailer"
        case (false, false):
            return "none"
        }
    }
}
