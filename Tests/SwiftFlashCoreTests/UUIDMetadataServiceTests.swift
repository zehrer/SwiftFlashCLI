import Foundation
import Testing
@testable import SwiftFlashCore

struct UUIDMetadataServiceTests {
    @Test
    func trailerRoundTripWorksWhenSlackIsAvailable() throws {
        let service = UUIDMetadataService()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try Data(count: 2 * 1024 * 1024).write(to: tempURL)
        let metadata = FlashUUIDMetadata(
            flashUUID: UUID(),
            deviceUUID: UUID().uuidString,
            deviceName: "Test Device",
            imagePath: "/tmp/test.iso",
            imageName: "test.iso",
            imageSHA256: "abc123",
            flashedAt: Date()
        )
        let device = DiskCandidate(
            devicePath: tempURL.path,
            rawDevicePath: tempURL.path,
            bsdName: "disk-test",
            physicalDeviceID: "scan-hint",
            name: "Test Device",
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

        let result = service.writeMetadata(
            metadata,
            imageSize: 512 * 1024,
            to: device,
            mountedPartitions: []
        )

        #expect(result.fileWritten == false)
        #expect(result.trailerWritten == true)
        let restored = service.readTrailerMetadata(
            fromDevicePath: tempURL.path,
            deviceSize: 2 * 1024 * 1024
        )
        #expect(restored?.schemaVersion == metadata.schemaVersion)
        #expect(restored?.flashUUID == metadata.flashUUID)
        #expect(restored?.deviceUUID == metadata.deviceUUID)
        #expect(restored?.deviceName == metadata.deviceName)
        #expect(restored?.imagePath == metadata.imagePath)
        #expect(restored?.imageName == metadata.imageName)
        #expect(restored?.imageSHA256 == metadata.imageSHA256)
    }

    @Test
    func trailerWriteIsSkippedWhenSlackIsTooSmall() throws {
        let service = UUIDMetadataService()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try Data(count: 2 * 1024 * 1024).write(to: tempURL)
        let metadata = FlashUUIDMetadata(
            flashUUID: UUID(),
            deviceUUID: UUID().uuidString,
            deviceName: "Test Device",
            imagePath: "/tmp/test.iso",
            imageName: "test.iso",
            imageSHA256: nil,
            flashedAt: Date()
        )
        let device = DiskCandidate(
            devicePath: tempURL.path,
            rawDevicePath: tempURL.path,
            bsdName: "disk-test",
            physicalDeviceID: "scan-hint",
            name: "Test Device",
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

        let result = service.writeMetadata(
            metadata,
            imageSize: Int64(2 * 1024 * 1024 - 512 * 1024),
            to: device,
            mountedPartitions: []
        )

        #expect(result.trailerWritten == false)
        #expect(
            service.readTrailerMetadata(
                fromDevicePath: tempURL.path,
                deviceSize: 2 * 1024 * 1024
            ) == nil
        )
    }

    @Test
    func ensureDeviceIdentityCreatesFileMetadataForWritableDevice() throws {
        let service = UUIDMetadataService()
        let mountURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: mountURL) }

        let device = DiskCandidate(
            devicePath: "/dev/disk-test",
            rawDevicePath: "/dev/rdisk-test",
            bsdName: "disk-test",
            physicalDeviceID: "scan-hint",
            name: "Untitled",
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
                    bsdName: "disk-tests1",
                    mountPoint: mountURL.path,
                    volumeName: "Untitled",
                    volumeKind: "msdos",
                    isMountable: true,
                    isWritable: true
                )
            ]
        )

        let identity = service.ensureDeviceIdentity(for: device)
        #expect(identity?.source == .created)
        #expect(identity?.metadata.deviceUUID.isEmpty == false)
        #expect(FileManager.default.fileExists(atPath: mountURL.appendingPathComponent(".uuid").path))
        let resolved = service.resolveIdentity(for: device)
        #expect(resolved?.source == .file)
        #expect(resolved?.metadata.deviceUUID == identity?.metadata.deviceUUID)
    }
}
