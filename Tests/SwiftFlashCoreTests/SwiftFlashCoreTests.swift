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
    func parserStartsREPLWithoutArguments() throws {
        let command = try CLIParser.parse(arguments: ["swiftflash"])
        #expect(command == .repl)
    }

    @Test
    func parserDefaultsMediaToListView() throws {
        let command = try CLIParser.parse(arguments: ["swiftflash", "media"])
        #expect(command == .mediaList)
    }

    @Test
    func parserSupportsLegacyDevicesAlias() throws {
        let command = try CLIParser.parse(arguments: ["swiftflash", "devices"])
        #expect(command == .mediaList)
    }

    @Test
    func parserSupportsKnownMediaView() throws {
        let command = try CLIParser.parse(arguments: ["swiftflash", "media", "known"])
        #expect(command == .mediaKnown)
    }

    @Test
    func parserSupportsMediaInfoCommand() throws {
        let command = try CLIParser.parse(arguments: ["swiftflash", "media", "info", "my-usb"])
        #expect(command == .mediaInfo(query: "my-usb"))
    }

    @Test
    func parserSupportsIdentifyCommand() throws {
        let command = try CLIParser.parse(arguments: ["swiftflash", "identify"])
        #expect(command == .mediaIdentify)
    }

    @Test
    func interactiveParserSupportsExitCommands() throws {
        #expect(try CLIParser.parseInteractive(line: "exit") == .exit)
        #expect(try CLIParser.parseInteractive(line: "quit") == .exit)
        #expect(try CLIParser.parseInteractive(line: "quite") == .exit)
    }

    @Test
    func interactiveParserSupportsQuotedArguments() throws {
        let command = try CLIParser.parseInteractive(line: "media type-add \"Installer Stick\"")
        #expect(command == .command(.mediaTypeAdd(name: "Installer Stick")))
    }

    @Test
    func parserSupportsMediaTypesCommand() throws {
        let command = try CLIParser.parse(arguments: ["swiftflash", "media", "types"])
        #expect(command == .mediaTypes)
    }

    @Test
    func parserSupportsMediaTypeAddCommand() throws {
        let command = try CLIParser.parse(arguments: ["swiftflash", "media", "type-add", "Installer Stick"])
        #expect(command == .mediaTypeAdd(name: "Installer Stick"))
    }

    @Test
    func parserSupportsMediaSetTypeCommand() throws {
        let command = try CLIParser.parse(arguments: ["swiftflash", "media", "set-type", "abc-123", "USB Stick"])
        #expect(command == .mediaSetType(id: "abc-123", typeName: "USB Stick"))
    }

    @Test
    func parserSupportsVerifyCommand() throws {
        let command = try CLIParser.parse(arguments: ["swiftflash", "verify", "image.iso", "/dev/disk4"])
        #expect(command == .verify(imagePath: "image.iso", devicePath: "/dev/disk4"))
    }

    @Test
    func parserSupportsHistoryClearCommand() throws {
        let command = try CLIParser.parse(arguments: ["swiftflash", "history", "clear"])
        #expect(command == .historyClear)
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

    @Test
    func configStartsWithPreconfiguredMediaTypes() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try AppConfigStore(configURL: tmp)
        let inventory = DeviceInventoryStore(configStore: store)

        #expect(inventory.allMediaTypes().map(\.name) == ["Micro SD Card", "SD Card", "USB Stick"])
    }

    @Test
    func deviceStoreCanAssignMediaType() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try AppConfigStore(configURL: tmp)
        let inventory = DeviceInventoryStore(configStore: store)

        try inventory.upsert(
            deviceUUID: "device-1",
            candidate: DiskCandidate(
                devicePath: "/dev/disk9",
                rawDevicePath: "/dev/rdisk9",
                bsdName: "disk9",
                physicalDeviceID: "scan-hint",
                name: "USB Reader",
                vendor: nil,
                model: nil,
                protocolName: nil,
                serialNumber: nil,
                size: 1024,
                isInternal: false,
                isRemovable: true,
                isEjectable: true,
                isWritable: true,
                isWhole: true,
                mediaUUID: nil,
                mediaKind: nil,
                partitions: []
            )
        )

        try inventory.setMediaType(id: "device-1", mediaTypeName: "USB Stick")
        #expect(inventory.findDevice(matching: "device-1")?.mediaTypeName == "USB Stick")
    }
}
