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
            physicalDeviceID: "device-1",
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

        try await service.flash(
            image: ImageDescriptor(url: imageURL, size: 1024 * 1024, checksum: nil),
            device: device
        ) { _ in }

        let history = historyStore.allHistory()
        #expect(history.count == 1)
        #expect(history[0].result == "success_without_uuid")
    }
}

private struct MockScanner: DeviceScanning {
    func scanEligibleDevices() throws -> [DiskCandidate] { [] }
    func findEligibleDevice(at path: String) throws -> DiskCandidate? {
        DiskCandidate(
            devicePath: "/dev/disk4",
            rawDevicePath: "/dev/rdisk4",
            bsdName: "disk4",
            physicalDeviceID: "device-1",
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
