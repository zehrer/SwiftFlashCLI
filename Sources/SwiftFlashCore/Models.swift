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
    public var physicalDeviceID: String
    public var customName: String?
    public var lastSeenSystemName: String
    public var vendor: String?
    public var model: String?
    public var protocolName: String?
    public var size: Int64
    public var firstSeen: Date
    public var lastSeen: Date
    public var lastKnownFlashUUID: UUID?

    public init(
        physicalDeviceID: String,
        customName: String? = nil,
        lastSeenSystemName: String,
        vendor: String? = nil,
        model: String? = nil,
        protocolName: String? = nil,
        size: Int64,
        firstSeen: Date,
        lastSeen: Date,
        lastKnownFlashUUID: UUID? = nil
    ) {
        self.physicalDeviceID = physicalDeviceID
        self.customName = customName
        self.lastSeenSystemName = lastSeenSystemName
        self.vendor = vendor
        self.model = model
        self.protocolName = protocolName
        self.size = size
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.lastKnownFlashUUID = lastKnownFlashUUID
    }

    public var displayName: String {
        customName ?? lastSeenSystemName
    }
}

public struct KnownFlashMedia: Codable, Equatable, Sendable {
    public var flashUUID: UUID
    public var lastImagePath: String
    public var lastImageName: String
    public var lastPhysicalDeviceID: String
    public var flashedAt: Date
    public var lastSeen: Date

    public init(
        flashUUID: UUID,
        lastImagePath: String,
        lastImageName: String,
        lastPhysicalDeviceID: String,
        flashedAt: Date,
        lastSeen: Date
    ) {
        self.flashUUID = flashUUID
        self.lastImagePath = lastImagePath
        self.lastImageName = lastImageName
        self.lastPhysicalDeviceID = lastPhysicalDeviceID
        self.flashedAt = flashedAt
        self.lastSeen = lastSeen
    }
}

public struct FlashHistoryEntry: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var finishedAt: Date
    public var imagePath: String
    public var imageName: String
    public var physicalDeviceID: String
    public var previousFlashUUID: UUID?
    public var newFlashUUID: UUID?
    public var uuidWriteSucceeded: Bool
    public var result: String

    public init(
        startedAt: Date,
        finishedAt: Date,
        imagePath: String,
        imageName: String,
        physicalDeviceID: String,
        previousFlashUUID: UUID?,
        newFlashUUID: UUID?,
        uuidWriteSucceeded: Bool,
        result: String
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.imagePath = imagePath
        self.imageName = imageName
        self.physicalDeviceID = physicalDeviceID
        self.previousFlashUUID = previousFlashUUID
        self.newFlashUUID = newFlashUUID
        self.uuidWriteSucceeded = uuidWriteSucceeded
        self.result = result
    }
}

public struct FlashUUIDMetadata: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var flashUUID: UUID
    public var physicalDeviceID: String
    public var physicalDeviceName: String?
    public var imagePath: String
    public var imageName: String
    public var imageSHA256: String?
    public var flashedAt: Date

    public init(
        schemaVersion: Int = 1,
        flashUUID: UUID,
        physicalDeviceID: String,
        physicalDeviceName: String?,
        imagePath: String,
        imageName: String,
        imageSHA256: String?,
        flashedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.flashUUID = flashUUID
        self.physicalDeviceID = physicalDeviceID
        self.physicalDeviceName = physicalDeviceName
        self.imagePath = imagePath
        self.imageName = imageName
        self.imageSHA256 = imageSHA256
        self.flashedAt = flashedAt
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
    case images
    case devices
    case deviceName(id: String, name: String)
    case deviceClearName(id: String)
    case history
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
