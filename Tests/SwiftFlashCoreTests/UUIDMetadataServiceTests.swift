import Darwin
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

    @Test
    func trailerReadReportsPermissionDenied() throws {
        let service = UUIDMetadataService()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            _ = chmod(tempURL.path, 0o600)
            try? FileManager.default.removeItem(at: tempURL)
        }

        try Data(count: 2 * 1024 * 1024).write(to: tempURL)
        #expect(chmod(tempURL.path, 0o000) == 0)

        let result = service.readTrailerMetadataResult(
            fromDevicePath: tempURL.path,
            deviceSize: 2 * 1024 * 1024
        )
        #expect(result == .permissionDenied)
    }

    @Test
    func trailerReadReportsCorruptPayload() throws {
        let service = UUIDMetadataService()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let deviceSize = 2 * 1024 * 1024
        var data = Data(count: deviceSize)
        let trailer = Data("SWFLASH-TRAILER-V1\n{not json".utf8)
        let offset = deviceSize - UUIDMetadataService.trailerBlockSize
        data.replaceSubrange(offset..<(offset + trailer.count), with: trailer)
        try data.write(to: tempURL)

        let result = service.readTrailerMetadataResult(
            fromDevicePath: tempURL.path,
            deviceSize: Int64(deviceSize)
        )
        #expect(result == .corrupt)
    }

    @Test
    func ensureDeviceIdentityDoesNotCreateWhenTrailerRequiresSudo() throws {
        let service = UUIDMetadataService()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            _ = chmod(tempURL.path, 0o600)
            try? FileManager.default.removeItem(at: tempURL)
        }

        try Data(count: 2 * 1024 * 1024).write(to: tempURL)
        #expect(chmod(tempURL.path, 0o000) == 0)

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

        let status = service.ensureDeviceIdentityStatus(for: device)
        #expect(status == .trailerRequiresSudo)
    }

    @Test
    func imageIdentityRoundTripKeepsUnknownFields() throws {
        let json = Data("""
        {"id": "sdcard-redox", "version": "0.9.1", "commit": "a1b2c3d", "board": {"name": "rpi4", "rev": 2}}
        """.utf8)
        let identity = try JSONCoding.decoder.decode(ImageIdentity.self, from: json)
        #expect(identity.displayLabel == "sdcard-redox 0.9.1")
        #expect(identity.additionalFields["commit"] == .string("a1b2c3d"))

        let reencoded = try JSONCoding.decoder.decode(ImageIdentity.self, from: JSONCoding.encoder.encode(identity))
        #expect(reencoded == identity)
        #expect(ImageIdentity().displayLabel == nil)
    }

    @Test
    func identifyKeepsImageBlockAndWritesIntoExistingUUIDFile() throws {
        let service = UUIDMetadataService()
        let firstMount = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bootMount = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: firstMount, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bootMount, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: firstMount)
            try? FileManager.default.removeItem(at: bootMount)
        }
        // Image-provided file, e.g. after writing the image with `dd`: no device UUID yet.
        try Data(#"{"schemaVersion": 1, "image": {"name": "Redox OS", "version": "0.9.1"}}"#.utf8)
            .write(to: bootMount.appendingPathComponent(".uuid"))

        let partitions = [firstMount, bootMount].enumerated().map { index, mount in
            PartitionVolume(
                bsdName: "disk-tests\(index + 1)",
                mountPoint: mount.path,
                volumeName: "P\(index + 1)",
                volumeKind: "msdos",
                isMountable: true,
                isWritable: true
            )
        }
        let device = DiskCandidate(
            devicePath: "/dev/disk-test",
            rawDevicePath: "/dev/rdisk-test",
            bsdName: "disk-test",
            physicalDeviceID: "scan-hint",
            name: "SD Card",
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
            partitions: partitions
        )

        #expect(service.resolveIdentityStatus(for: device) == .unassigned)
        #expect(service.readImageIdentity(from: partitions)?.displayLabel == "Redox OS 0.9.1")

        let identity = try #require(service.ensureDeviceIdentity(for: device))
        #expect(identity.metadata.image?.version == "0.9.1")
        #expect(!FileManager.default.fileExists(atPath: firstMount.appendingPathComponent(".uuid").path))
        let resolved = service.resolveIdentity(for: device)
        #expect(resolved?.metadata.deviceUUID == identity.metadata.deviceUUID)
        #expect(resolved?.metadata.image?.name == "Redox OS")
    }
}
