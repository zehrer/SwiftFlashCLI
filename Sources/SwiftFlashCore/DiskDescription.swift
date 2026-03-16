import DiskArbitration
import Foundation

struct DiskDescription {
    let dictionary: [String: Any]?

    init(_ dictionary: [String: Any]?) {
        self.dictionary = dictionary
    }

    var volumeName: String? { string(for: kDADiskDescriptionVolumeNameKey) }
    var volumePath: String? { path(for: kDADiskDescriptionVolumePathKey) }
    var volumeKind: String? { string(for: kDADiskDescriptionVolumeKindKey) }
    var isMountable: Bool? { bool(for: kDADiskDescriptionVolumeMountableKey) }
    var volumeUUID: String? { string(for: kDADiskDescriptionVolumeUUIDKey) }

    var mediaUUID: String? { string(for: kDADiskDescriptionMediaUUIDKey) }
    var mediaName: String? { string(for: kDADiskDescriptionMediaNameKey) }
    var mediaKind: String? { string(for: kDADiskDescriptionMediaKindKey) }
    var mediaSize: UInt64? { uint64(for: kDADiskDescriptionMediaSizeKey) }
    var isEjectable: Bool? { bool(for: kDADiskDescriptionMediaEjectableKey) }
    var isRemovable: Bool? { bool(for: kDADiskDescriptionMediaRemovableKey) }
    var isWhole: Bool? { bool(for: kDADiskDescriptionMediaWholeKey) }
    var isWritable: Bool? { bool(for: kDADiskDescriptionMediaWritableKey) }

    var deviceModel: String? { string(for: kDADiskDescriptionDeviceModelKey) }
    var deviceProtocol: String? { string(for: kDADiskDescriptionDeviceProtocolKey) }
    var deviceRevision: String? { string(for: kDADiskDescriptionDeviceRevisionKey) }
    var deviceVendor: String? { string(for: kDADiskDescriptionDeviceVendorKey) }
    var isInternal: Bool? { bool(for: kDADiskDescriptionDeviceInternalKey) }
}

private extension DiskDescription {
    func bool(for key: CFString) -> Bool? {
        (dictionary?[key as String] as? NSNumber)?.boolValue
    }

    func string(for key: CFString) -> String? {
        dictionary?[key as String] as? String
    }

    func path(for key: CFString) -> String? {
        if let url = dictionary?[key as String] as? URL {
            return url.path
        }
        return dictionary?[key as String] as? String
    }

    func uint64(for key: CFString) -> UInt64? {
        if let value = dictionary?[key as String] as? UInt64 {
            return value
        }
        if let value = dictionary?[key as String] as? Int64, value >= 0 {
            return UInt64(value)
        }
        if let value = dictionary?[key as String] as? NSNumber {
            let intValue = value.int64Value
            return intValue >= 0 ? UInt64(intValue) : nil
        }
        return nil
    }
}
