import Foundation
import Testing
@testable import SwiftFlashCore

struct FlashServiceTests {
    @Test
    func serviceRecordsPartialSuccessWhenUUIDCannotBeWritten() async throws {
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let configStore = try AppConfigStore(configURL: configURL)
        let imageStore = ImageCatalogStore(configStore: configStore)
        let deviceStore = DeviceInventoryStore(configStore: configStore)
        let historyStore = FlashHistoryStore(configStore: configStore)
        let service = FlashService(
            scanner: MockScanner(),
            deviceManager: MockDeviceManager(),
            writer: MockWriter(),
            verifier: MockVerifier(),
            uuidService: UUIDMetadataService(),
            imageStore: imageStore,
            deviceStore: deviceStore,
            historyStore: historyStore
        )

        let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iso")
        try Data(repeating: 0, count: 1024 * 1024).write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let device = DiskCandidate(
            devicePath: "/dev/disk4",
            rawDevicePath: "/dev/rdisk4",
            bsdName: "disk4",
            physicalDeviceID: "scan-hint-1",
            name: "USB Stick",
            vendor: nil,
            model: nil,
            protocolName: nil,
            serialNumber: nil,
            size: 2 * 1024 * 1024,
            isInternal: false,
            isRemovable: true,
            isEjectable: true,
            isWritable: true,
            isWhole: true,
            mediaUUID: nil,
            mediaKind: nil,
            partitions: []
        )

        let completion = try await service.flash(
            image: ImageDescriptor(url: imageURL, size: 1024 * 1024, checksum: nil),
            device: device,
            writeProgress: { _ in },
            promptForVerification: { false },
            verifyProgress: { _ in }
        )

        let history = historyStore.allHistory()
        #expect(history.count == 1)
        #expect(history[0].result == "success_metadata_none")
        #expect(completion.previousIdentity == nil)
        #expect(completion.metadata.deviceUUID.isEmpty == false)
    }

    @Test
    func serviceReusesExistingDeviceUUIDFromUUIDFile() async throws {
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let configStore = try AppConfigStore(configURL: configURL)
        let imageStore = ImageCatalogStore(configStore: configStore)
        let deviceStore = DeviceInventoryStore(configStore: configStore)
        let historyStore = FlashHistoryStore(configStore: configStore)
        let service = FlashService(
            scanner: MockScanner(),
            deviceManager: MockDeviceManager(),
            writer: MockWriter(),
            verifier: MockVerifier(),
            uuidService: UUIDMetadataService(),
            imageStore: imageStore,
            deviceStore: deviceStore,
            historyStore: historyStore
        )

        let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iso")
        let mountURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try Data(repeating: 0, count: 1024 * 1024).write(to: imageURL)
        try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: imageURL)
            try? FileManager.default.removeItem(at: mountURL)
        }

        let existingMetadata = FlashUUIDMetadata(
            flashUUID: UUID(),
            deviceUUID: UUID().uuidString,
            deviceName: "USB Stick",
            imagePath: "/tmp/old.iso",
            imageName: "old.iso",
            imageSHA256: nil,
            flashedAt: Date()
        )
        let metadataData = try JSONCoding.encoder.encode(existingMetadata)
        try metadataData.write(to: mountURL.appendingPathComponent(".uuid"))

        let device = DiskCandidate(
            devicePath: "/dev/disk4",
            rawDevicePath: "/dev/rdisk4",
            bsdName: "disk4",
            physicalDeviceID: "scan-hint-1",
            name: "USB Stick",
            vendor: nil,
            model: nil,
            protocolName: nil,
            serialNumber: nil,
            size: 2 * 1024 * 1024,
            isInternal: false,
            isRemovable: true,
            isEjectable: true,
            isWritable: true,
            isWhole: true,
            mediaUUID: nil,
            mediaKind: nil,
            partitions: [
                PartitionVolume(
                    bsdName: "disk4s1",
                    mountPoint: mountURL.path,
                    volumeName: "UNTITLED",
                    volumeKind: "msdos",
                    isMountable: true,
                    isWritable: true
                )
            ]
        )

        let completion = try await service.flash(
            image: ImageDescriptor(url: imageURL, size: 1024 * 1024, checksum: nil),
            device: device,
            writeProgress: { _ in },
            promptForVerification: { false },
            verifyProgress: { _ in }
        )

        #expect(completion.previousIdentity?.source == .file)
        #expect(completion.previousIdentity?.metadata.deviceUUID == existingMetadata.deviceUUID)
        #expect(completion.metadata.deviceUUID == existingMetadata.deviceUUID)
    }

    @Test
    func historyStoreCanBeCleared() throws {
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let configStore = try AppConfigStore(configURL: configURL)
        let historyStore = FlashHistoryStore(configStore: configStore)

        try historyStore.add(
            FlashHistoryEntry(
                startedAt: Date(),
                finishedAt: Date(),
                imagePath: "/tmp/test.iso",
                imageName: "test.iso",
                deviceUUID: UUID().uuidString,
                previousFlashUUID: nil,
                newFlashUUID: UUID(),
                uuidWriteSucceeded: false,
                result: "success_metadata_none"
            )
        )

        #expect(historyStore.allHistory().count == 1)
        try historyStore.clear()
        #expect(historyStore.allHistory().isEmpty)
    }
}

private struct MockScanner: DeviceScanning {
    func scanEligibleDevices() throws -> [DiskCandidate] { [] }
    func findEligibleDevice(at path: String) throws -> DiskCandidate? {
        DiskCandidate(
            devicePath: "/dev/disk4",
            rawDevicePath: "/dev/rdisk4",
            bsdName: "disk4",
            physicalDeviceID: "scan-hint-1",
            name: "USB Stick",
            vendor: nil,
            model: nil,
            protocolName: nil,
            serialNumber: nil,
            size: 2 * 1024 * 1024,
            isInternal: false,
            isRemovable: true,
            isEjectable: true,
            isWritable: true,
            isWhole: true,
            mediaUUID: nil,
            mediaKind: nil,
            partitions: []
        )
    }
}

private struct MockDeviceManager: DeviceManaging {
    func unmountWholeDisk(_ device: DiskCandidate) async throws {}
    func mountPartition(_ bsdName: String) async throws {}
}

private struct MockWriter: RawImageWriting {
    func writeImage(from imageURL: URL, to devicePath: String, progress: @escaping @Sendable (Double) -> Void) throws {
        progress(1.0)
    }
}

private struct MockVerifier: RawImageVerifying {
    func verifyImage(from imageURL: URL, to devicePath: String, progress: @escaping @Sendable (Double) -> Void) throws {
        progress(1.0)
    }
}
