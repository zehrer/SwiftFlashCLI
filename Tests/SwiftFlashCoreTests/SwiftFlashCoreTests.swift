import Foundation
import Testing
@testable import SwiftFlashCore

struct SwiftFlashCoreTests {
    @Test
    func parserSupportsBareInvocation() throws {
        let command = try CLIParser.parse(arguments: ["swiftflash", "image.iso", "/dev/disk4"])
        #expect(command == .flash(imagePath: "image.iso", devicePath: "/dev/disk4", skipConfirmation: false))
    }

    @Test
    func pathResolverUsesSudoUserHome() throws {
        let url = try ConfigPathResolver.defaultConfigURL(
            env: ["HOME": "/var/root", "SUDO_USER": NSUserName()],
            effectiveUserID: 0
        )
        #expect(url.path.contains(NSHomeDirectory()))
        #expect(url.path.hasSuffix("/.swiftflash/config.json"))
    }

    @Test
    func filterEligibleDevicesExcludesInternalAndImages() {
        let snapshots = [
            RawDiskSnapshot(
                devicePath: "/dev/disk1",
                bsdName: "disk1",
                name: "Internal SSD",
                size: 100,
                isInternal: true,
                isRemovable: false,
                isEjectable: false,
                isWritable: true,
                isWhole: true
            ),
            RawDiskSnapshot(
                devicePath: "/dev/disk2",
                bsdName: "disk2",
                name: "Disk Image",
                size: 100,
                isInternal: false,
                isRemovable: true,
                isEjectable: true,
                isWritable: true,
                isWhole: true,
                mediaKind: "Disk Image"
            ),
            RawDiskSnapshot(
                devicePath: "/dev/disk3",
                bsdName: "disk3",
                name: "USB Stick",
                size: 100,
                isInternal: false,
                isRemovable: true,
                isEjectable: true,
                isWritable: true,
                isWhole: true
            )
        ]

        let filtered = DeviceScanner.filterEligibleDevices(from: snapshots)
        #expect(filtered.count == 1)
        #expect(filtered.first?.devicePath == "/dev/disk3")
    }

    @Test
    func imageStoreOrdersByRecency() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try AppConfigStore(configURL: tmp)
        let images = ImageCatalogStore(configStore: store)

        try images.remember(image: ImageDescriptor(url: URL(fileURLWithPath: "/tmp/a.iso"), size: 10, checksum: nil))
        try images.remember(image: ImageDescriptor(url: URL(fileURLWithPath: "/tmp/b.iso"), size: 10, checksum: nil))

        #expect(images.allImages().map(\.path) == ["/tmp/b.iso", "/tmp/a.iso"])
    }
}
