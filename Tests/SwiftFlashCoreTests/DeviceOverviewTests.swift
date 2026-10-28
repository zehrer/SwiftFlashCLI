import Foundation
import Testing
@testable import SwiftFlashCore

struct DeviceOverviewTests {
    private let flashedAt = Date(timeIntervalSince1970: 1_793_000_000)

    @Test
    func knownMediumShowsNameTypeAndCurrentImage() {
        let metadata = FlashUUIDMetadata(
            flashUUID: UUID(),
            deviceUUID: "0F9A6091",
            deviceName: "Generic MassStorageClass Media",
            imagePath: "http://host/sdcard-redox.img.xz",
            imageName: "sdcard-redox.img",
            imageSHA256: nil,
            flashedAt: flashedAt,
            image: ImageIdentity(name: "Redox OS", version: "0.9.1")
        )
        let known = KnownPhysicalDevice(
            deviceUUID: "0F9A6091",
            customName: "Redox SD",
            mediaTypeName: "SD Card",
            size: 32,
            firstSeen: flashedAt,
            lastSeen: flashedAt
        )

        let overview = DeviceOverview.make(
            device: device(volumes: ["BOOT"]),
            identityStatus: .identified(ResolvedDeviceIdentity(metadata: metadata, source: .file)),
            knownDevice: known,
            imageIdentity: nil,
            formatDate: { _ in "26 Oct 2026" }
        )

        #expect(overview.title == "Redox SD")
        #expect(overview.details == [
            "Known medium: Redox SD [SD Card], device-uuid 0F9A6091",
            "Currently on it: Redox OS 0.9.1 (sdcard-redox.img), flashed 26 Oct 2026",
        ])
        #expect(overview.currentContent == "Redox OS 0.9.1 (sdcard-redox.img), flashed 26 Oct 2026")
    }

    @Test
    func knownMediumWithoutCustomNameKeepsDeviceName() {
        let metadata = FlashUUIDMetadata(
            flashUUID: nil,
            deviceUUID: "ABC",
            deviceName: nil,
            imagePath: "",
            imageName: "",
            imageSHA256: nil,
            flashedAt: flashedAt
        )
        let known = KnownPhysicalDevice(deviceUUID: "ABC", size: 32, firstSeen: flashedAt, lastSeen: flashedAt)

        let overview = DeviceOverview.make(
            device: device(volumes: ["UNTITLED"]),
            identityStatus: .identified(ResolvedDeviceIdentity(metadata: metadata, source: .file)),
            knownDevice: known,
            imageIdentity: nil
        )

        #expect(overview.title == "Generic Media")
        #expect(overview.details == [
            "Known medium: unnamed, device-uuid ABC",
            "Currently on it: volumes UNTITLED",
        ])
    }

    @Test
    func unknownMediumShowsImageShippedOnIt() {
        let overview = DeviceOverview.make(
            device: device(volumes: ["BOOT"]),
            identityStatus: .unassigned,
            knownDevice: nil,
            imageIdentity: ImageIdentity(id: "sdcard-redox", version: "0.9.0")
        )

        #expect(overview.details == ["Unknown medium", "Currently on it: sdcard-redox 0.9.0"])
    }

    @Test
    func emptyUnknownMediumHasNoContentLine() {
        let overview = DeviceOverview.make(
            device: device(volumes: []),
            identityStatus: .trailerRequiresSudo,
            knownDevice: nil,
            imageIdentity: nil
        )

        #expect(overview.details == ["Unknown medium (sudo required to read trailer metadata)"])
        #expect(overview.currentContent == nil)
    }

    private func device(volumes: [String]) -> DiskCandidate {
        DiskCandidate(
            devicePath: "/dev/disk6",
            rawDevicePath: "/dev/rdisk6",
            bsdName: "disk6",
            physicalDeviceID: "scan-hint",
            name: "Generic Media",
            vendor: nil,
            model: nil,
            protocolName: nil,
            serialNumber: nil,
            size: 32 * 1024 * 1024 * 1024,
            isInternal: false,
            isRemovable: true,
            isEjectable: true,
            isWritable: true,
            isWhole: true,
            mediaUUID: nil,
            mediaKind: nil,
            partitions: volumes.enumerated().map { index, name in
                PartitionVolume(
                    bsdName: "disk6s\(index + 1)",
                    mountPoint: nil,
                    volumeName: name,
                    volumeKind: "msdos",
                    isMountable: true,
                    isWritable: true
                )
            }
        )
    }
}
