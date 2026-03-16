import CryptoKit
import DiskArbitration
import Foundation
import IOKit
import IOKit.storage

public protocol DeviceScanning {
    func scanEligibleDevices() throws -> [DiskCandidate]
    func findEligibleDevice(at path: String) throws -> DiskCandidate?
}

public final class DeviceScanner: DeviceScanning {
    public init() {}

    public func scanEligibleDevices() throws -> [DiskCandidate] {
        Self.filterEligibleDevices(from: try scanRawDevices())
    }

    public func findEligibleDevice(at path: String) throws -> DiskCandidate? {
        let normalized = Self.normalizeDevicePath(path)
        return try scanEligibleDevices().first {
            $0.devicePath == normalized || $0.rawDevicePath == normalized
        }
    }

    func scanRawDevices() throws -> [RawDiskSnapshot] {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(kIOMediaClass),
            &iterator
        )
        guard result == KERN_SUCCESS else {
            throw FlashError.ioFailed("IOKit enumeration failed with code \(result)")
        }
        defer { IOObjectRelease(iterator) }

        let session = DASessionCreate(kCFAllocatorDefault)
        var snapshots: [RawDiskSnapshot] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let props = Self.properties(for: service) else {
                continue
            }

            guard let bsdName = props[kIOBSDNameKey as String] as? String else {
                continue
            }

            let devicePath = "/dev/\(bsdName)"
            let description = Self.diskDescription(devicePath: devicePath, session: session)
            let diskDescription = DiskDescription(description)
            let partitions = Self.partitions(for: bsdName, session: session)
            let serialNumber = Self.serialNumber(for: service)
            let snapshot = RawDiskSnapshot(
                devicePath: devicePath,
                bsdName: bsdName,
                name: Self.deviceName(
                    props: props,
                    description: diskDescription,
                    fallbackService: service
                ),
                vendor: diskDescription.deviceVendor,
                model: diskDescription.deviceModel,
                protocolName: diskDescription.deviceProtocol,
                serialNumber: serialNumber,
                size: Int64(diskDescription.mediaSize ?? 0),
                isInternal: diskDescription.isInternal ?? false,
                isRemovable: diskDescription.isRemovable ?? false,
                isEjectable: diskDescription.isEjectable ?? false,
                isWritable: diskDescription.isWritable ?? false,
                isWhole: diskDescription.isWhole ?? false,
                mediaUUID: diskDescription.mediaUUID,
                mediaKind: diskDescription.mediaKind,
                partitions: partitions
            )
            snapshots.append(snapshot)
        }

        return snapshots
    }

    public static func filterEligibleDevices(from snapshots: [RawDiskSnapshot]) -> [DiskCandidate] {
        snapshots
            .filter { $0.isWhole }
            .filter { !$0.isInternal }
            .filter { $0.isWritable }
            .filter { !$0.devicePath.contains("/dev/disk") || !$0.name.localizedCaseInsensitiveContains("disk image") }
            .filter {
                !($0.mediaKind?.localizedCaseInsensitiveContains("disk image") ?? false) &&
                !($0.model?.localizedCaseInsensitiveContains("disk image") ?? false)
            }
            .map { snapshot in
                let rawPath = Self.rawDevicePath(for: snapshot.devicePath)
                return DiskCandidate(
                    devicePath: snapshot.devicePath,
                    rawDevicePath: rawPath,
                    bsdName: snapshot.bsdName,
                    physicalDeviceID: Self.stableDeviceID(
                        mediaUUID: snapshot.mediaUUID,
                        serialNumber: snapshot.serialNumber,
                        vendor: snapshot.vendor,
                        model: snapshot.model,
                        size: snapshot.size,
                        protocolName: snapshot.protocolName
                    ),
                    name: snapshot.name,
                    vendor: snapshot.vendor,
                    model: snapshot.model,
                    protocolName: snapshot.protocolName,
                    serialNumber: snapshot.serialNumber,
                    size: snapshot.size,
                    isInternal: snapshot.isInternal,
                    isRemovable: snapshot.isRemovable,
                    isEjectable: snapshot.isEjectable,
                    isWritable: snapshot.isWritable,
                    isWhole: snapshot.isWhole,
                    mediaUUID: snapshot.mediaUUID,
                    mediaKind: snapshot.mediaKind,
                    partitions: snapshot.partitions
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func normalizeDevicePath(_ path: String) -> String {
        if path.hasPrefix("/dev/rdisk") {
            return path.replacingOccurrences(of: "/dev/rdisk", with: "/dev/disk")
        }
        return path
    }

    static func rawDevicePath(for devicePath: String) -> String {
        let rawPath = devicePath.replacingOccurrences(of: "/dev/disk", with: "/dev/rdisk")
        return FileManager.default.fileExists(atPath: rawPath) ? rawPath : devicePath
    }

    static func stableDeviceID(
        mediaUUID: String?,
        serialNumber: String?,
        vendor: String?,
        model: String?,
        size: Int64,
        protocolName: String?
    ) -> String {
        if let mediaUUID, !mediaUUID.isEmpty {
            return mediaUUID
        }
        if let serialNumber, !serialNumber.isEmpty {
            return serialNumber
        }

        let fallback = [vendor ?? "", model ?? "", "\(size)", protocolName ?? ""]
            .joined(separator: "|")
        return Hashing.sha256Hex(Data(fallback.utf8))
    }
}

private extension DeviceScanner {
    static func properties(for service: io_object_t) -> [String: Any]? {
        var props: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS else {
            return nil
        }
        return props?.takeRetainedValue() as? [String: Any]
    }

    static func diskDescription(devicePath: String, session: DASession?) -> [String: Any]? {
        guard let session else { return nil }
        let bsdName = normalizeDevicePath(devicePath).replacingOccurrences(of: "/dev/", with: "")
        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) else {
            return nil
        }
        return DADiskCopyDescription(disk) as? [String: Any]
    }

    static func partitions(for parentBSDName: String, session: DASession?) -> [PartitionVolume] {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(kIOMediaClass),
            &iterator
        )
        guard result == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var volumes: [PartitionVolume] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let props = properties(for: service),
                  let bsdName = props[kIOBSDNameKey as String] as? String,
                  bsdName.hasPrefix(parentBSDName + "s")
            else {
                continue
            }

            let desc = DiskDescription(
                diskDescription(devicePath: "/dev/\(bsdName)", session: session)
            )
            volumes.append(
                PartitionVolume(
                    bsdName: bsdName,
                    mountPoint: desc.volumePath,
                    volumeName: desc.volumeName ?? desc.mediaName,
                    volumeKind: desc.volumeKind,
                    isMountable: desc.isMountable ?? false,
                    isWritable: desc.isWritable ?? false
                )
            )
        }
        return volumes.sorted { $0.bsdName < $1.bsdName }
    }

    static func deviceName(
        props: [String: Any],
        description: DiskDescription,
        fallbackService: io_object_t
    ) -> String {
        if let volume = description.volumeName, !volume.isEmpty {
            return volume
        }
        if let media = description.mediaName, !media.isEmpty {
            return media
        }
        if let model = description.deviceModel, !model.isEmpty {
            return model
        }
        if let product = parentString(
            keys: ["USB Product Name", "Product Name", "product-name", "kUSBProductString"],
            service: fallbackService
        ) {
            return product
        }
        if let name = props["BSD Name"] as? String {
            return name
        }
        return "Unknown Device"
    }

    static func serialNumber(for service: io_object_t) -> String? {
        parentString(
            keys: ["USB Serial Number", "Serial Number", "kUSBSerialNumberString", "serial-number"],
            service: service
        )
    }

    static func parentString(keys: [String], service: io_object_t) -> String? {
        var current = service
        var parent: io_registry_entry_t = 0
        while IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS {
            defer {
                if current != service {
                    IOObjectRelease(current)
                }
                current = parent
                parent = 0
            }
            guard let props = properties(for: current) else {
                continue
            }
            for key in keys {
                if let value = props[key] as? String, !value.isEmpty {
                    return value
                }
            }
        }
        if current != service {
            IOObjectRelease(current)
        }
        return nil
    }
}
