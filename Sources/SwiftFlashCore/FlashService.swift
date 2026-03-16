import Foundation

public final class FlashService {
    private let scanner: DeviceScanning
    private let deviceManager: DeviceManaging
    private let writer: RawImageWriting
    private let uuidService: UUIDMetadataService
    private let imageStore: ImageCatalogStore
    private let deviceStore: DeviceInventoryStore
    private let historyStore: FlashHistoryStore

    public init(
        scanner: DeviceScanning,
        deviceManager: DeviceManaging,
        writer: RawImageWriting,
        uuidService: UUIDMetadataService,
        imageStore: ImageCatalogStore,
        deviceStore: DeviceInventoryStore,
        historyStore: FlashHistoryStore
    ) {
        self.scanner = scanner
        self.deviceManager = deviceManager
        self.writer = writer
        self.uuidService = uuidService
        self.imageStore = imageStore
        self.deviceStore = deviceStore
        self.historyStore = historyStore
    }

    public func flash(
        image: ImageDescriptor,
        device: DiskCandidate,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let startedAt = Date()
        let previousMetadata = uuidService.readExistingMetadata(from: device.partitions)

        do {
            guard image.size <= device.size else {
                throw FlashError.imageTooLarge(imageSize: image.size, deviceSize: device.size)
            }

            try await deviceManager.unmountWholeDisk(device)
            try writer.writeImage(from: image.url, to: device.rawDevicePath, progress: progress)

            let refreshed = try await rescanDevice(path: device.devicePath)
            let mounted = try await mountWritablePartitions(of: refreshed ?? device)
            let checksum = try? ImageSupport.calculateSHA256(for: image.url)
            let metadata = FlashUUIDMetadata(
                flashUUID: UUID(),
                physicalDeviceID: device.physicalDeviceID,
                physicalDeviceName: device.displayName,
                imagePath: image.url.path,
                imageName: image.name,
                imageSHA256: checksum,
                flashedAt: Date()
            )
            let uuidWriteSucceeded = uuidService.writeMetadata(metadata, to: mounted)

            try imageStore.remember(image: ImageDescriptor(url: image.url, size: image.size, checksum: checksum))
            try deviceStore.upsert(candidate: device, flashUUID: metadata.flashUUID)
            try historyStore.upsertFlashMedia(
                KnownFlashMedia(
                    flashUUID: metadata.flashUUID,
                    lastImagePath: image.url.path,
                    lastImageName: image.name,
                    lastPhysicalDeviceID: device.physicalDeviceID,
                    flashedAt: metadata.flashedAt,
                    lastSeen: metadata.flashedAt
                )
            )
            try historyStore.add(
                FlashHistoryEntry(
                    startedAt: startedAt,
                    finishedAt: Date(),
                    imagePath: image.url.path,
                    imageName: image.name,
                    physicalDeviceID: device.physicalDeviceID,
                    previousFlashUUID: previousMetadata?.flashUUID,
                    newFlashUUID: metadata.flashUUID,
                    uuidWriteSucceeded: uuidWriteSucceeded,
                    result: uuidWriteSucceeded ? "success" : "success_without_uuid"
                )
            )
        } catch {
            try? historyStore.add(
                FlashHistoryEntry(
                    startedAt: startedAt,
                    finishedAt: Date(),
                    imagePath: image.url.path,
                    imageName: image.name,
                    physicalDeviceID: device.physicalDeviceID,
                    previousFlashUUID: previousMetadata?.flashUUID,
                    newFlashUUID: nil,
                    uuidWriteSucceeded: false,
                    result: "failed: \(error.localizedDescription)"
                )
            )
            throw error
        }
    }

    private func rescanDevice(path: String) async throws -> DiskCandidate? {
        for _ in 0..<5 {
            if let device = try scanner.findEligibleDevice(at: path) {
                return device
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return try scanner.findEligibleDevice(at: path)
    }

    private func mountWritablePartitions(of device: DiskCandidate) async throws -> [PartitionVolume] {
        var current = device
        for partition in current.partitions where partition.mountPoint == nil && partition.isMountable {
            try? await deviceManager.mountPartition(partition.bsdName)
        }
        if let rescanned = try await rescanDevice(path: device.devicePath) {
            current = rescanned
        }
        return current.partitions
    }
}
