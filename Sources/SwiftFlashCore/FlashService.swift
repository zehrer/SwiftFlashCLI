import Foundation

public final class FlashService {
    private let scanner: DeviceScanning
    private let deviceManager: DeviceManaging
    private let writer: RawImageWriting
    private let verifier: RawImageVerifying
    private let uuidService: UUIDMetadataService
    private let imageStore: ImageCatalogStore
    private let deviceStore: DeviceInventoryStore
    private let historyStore: FlashHistoryStore

    public init(
        scanner: DeviceScanning,
        deviceManager: DeviceManaging,
        writer: RawImageWriting,
        verifier: RawImageVerifying,
        uuidService: UUIDMetadataService,
        imageStore: ImageCatalogStore,
        deviceStore: DeviceInventoryStore,
        historyStore: FlashHistoryStore
    ) {
        self.scanner = scanner
        self.deviceManager = deviceManager
        self.writer = writer
        self.verifier = verifier
        self.uuidService = uuidService
        self.imageStore = imageStore
        self.deviceStore = deviceStore
        self.historyStore = historyStore
    }

    public func flash(
        image: ImageDescriptor,
        device: DiskCandidate,
        writeProgress: @escaping @Sendable (Double) -> Void,
        promptForVerification: @escaping @Sendable () async throws -> Bool,
        verifyProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> FlashCompletion {
        let startedAt = Date()
        let previousIdentity = uuidService.resolveIdentity(for: device)
        let previousMetadata = previousIdentity?.metadata
        var didVerify = false

        do {
            guard image.size <= device.size else {
                throw FlashError.imageTooLarge(imageSize: image.size, deviceSize: device.size)
            }

            try await deviceManager.unmountWholeDisk(device)
            try writer.writeImage(from: image.url, to: device.rawDevicePath, progress: writeProgress)

            if try await promptForVerification() {
                try verifier.verifyImage(
                    from: image.url,
                    to: device.rawDevicePath,
                    progress: verifyProgress
                )
                didVerify = true
            }

            let refreshed = try await rescanDevice(path: device.devicePath)
            let mounted = try await mountWritablePartitions(of: refreshed ?? device)
            let checksum = try? ImageSupport.calculateSHA256(for: image.url)
            let deviceUUID = previousMetadata?.deviceUUID ?? UUID().uuidString
            let metadata = FlashUUIDMetadata(
                flashUUID: UUID(),
                deviceUUID: deviceUUID,
                deviceName: device.displayName,
                imagePath: image.url.path,
                imageName: image.name,
                imageSHA256: checksum,
                flashedAt: Date()
            )
            let writeResult = uuidService.writeMetadata(
                metadata,
                imageSize: image.size,
                to: refreshed ?? device,
                mountedPartitions: mounted
            )

            try imageStore.remember(image: ImageDescriptor(url: image.url, size: image.size, checksum: checksum))
            try deviceStore.upsert(deviceUUID: deviceUUID, candidate: refreshed ?? device)
            try historyStore.upsertFlashMedia(
                KnownFlashMedia(
                    flashUUID: metadata.flashUUID ?? UUID(),
                    lastImagePath: image.url.path,
                    lastImageName: image.name,
                    deviceUUID: deviceUUID,
                    flashedAt: metadata.flashedAt,
                    lastSeen: metadata.flashedAt
                )
            )
            let result = historyResult(writeResult: writeResult, verified: didVerify)
            try historyStore.add(
                FlashHistoryEntry(
                    startedAt: startedAt,
                    finishedAt: Date(),
                    imagePath: image.url.path,
                    imageName: image.name,
                    deviceUUID: deviceUUID,
                    previousFlashUUID: previousMetadata?.flashUUID,
                    newFlashUUID: metadata.flashUUID,
                    uuidWriteSucceeded: writeResult.anyWritten,
                    result: result
                )
            )
            return FlashCompletion(
                previousIdentity: previousIdentity,
                metadata: metadata,
                writeResult: writeResult,
                verified: didVerify
            )
        } catch {
            try? historyStore.add(
                FlashHistoryEntry(
                    startedAt: startedAt,
                    finishedAt: Date(),
                    imagePath: image.url.path,
                    imageName: image.name,
                    deviceUUID: previousMetadata?.deviceUUID ?? "unknown",
                    previousFlashUUID: previousMetadata?.flashUUID,
                    newFlashUUID: nil,
                    uuidWriteSucceeded: false,
                    result: "failed: \(error.localizedDescription)"
                )
            )
            throw error
        }
    }

    public func verify(
        image: ImageDescriptor,
        device: DiskCandidate,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard image.size <= device.size else {
            throw FlashError.imageTooLarge(imageSize: image.size, deviceSize: device.size)
        }

        try await deviceManager.unmountWholeDisk(device)
        try verifier.verifyImage(from: image.url, to: device.rawDevicePath, progress: progress)

        if let rescanned = try await rescanDevice(path: device.devicePath) {
            _ = try await mountWritablePartitions(of: rescanned)
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

    private func historyResult(writeResult: MetadataWriteResult, verified: Bool) -> String {
        let metadataSuffix: String
        switch (writeResult.fileWritten, writeResult.trailerWritten) {
        case (true, true):
            metadataSuffix = "metadata_file_and_trailer"
        case (true, false):
            metadataSuffix = "metadata_file_only"
        case (false, true):
            metadataSuffix = "metadata_trailer_only"
        case (false, false):
            metadataSuffix = "metadata_none"
        }

        if verified {
            return "success_verified_\(metadataSuffix)"
        }
        return "success_\(metadataSuffix)"
    }
}
