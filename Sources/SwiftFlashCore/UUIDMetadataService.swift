import Foundation
import Darwin

public final class UUIDMetadataService {
    public static let trailerBlockSize = 4096
    public static let minimumTrailerSlack = 1024 * 1024
    private static let trailerMagic = "SWFLASH-TRAILER-V1\n"

    enum TrailerMetadataReadResult: Equatable {
        case metadata(FlashUUIDMetadata)
        case notPresent
        case permissionDenied
    }

    public init() {}

    public func readExistingMetadata(from partitions: [PartitionVolume]) -> FlashUUIDMetadata? {
        for partition in partitions {
            guard let mountPoint = partition.mountPoint else { continue }
            let url = URL(fileURLWithPath: mountPoint).appendingPathComponent(".uuid")
            guard let data = try? Data(contentsOf: url) else { continue }
            if let metadata = try? JSONCoding.decoder.decode(FlashUUIDMetadata.self, from: data) {
                return metadata
            }
        }
        return nil
    }

    public func readExistingMetadata(from device: DiskCandidate) -> FlashUUIDMetadata? {
        resolveIdentityStatus(for: device).resolvedIdentity?.metadata
    }

    public func resolveIdentity(for device: DiskCandidate) -> ResolvedDeviceIdentity? {
        resolveIdentityStatus(for: device).resolvedIdentity
    }

    public func resolveIdentityStatus(for device: DiskCandidate) -> DeviceIdentityStatus {
        if let metadata = readExistingMetadata(from: device.partitions) {
            return .identified(ResolvedDeviceIdentity(metadata: metadata, source: .file))
        }
        switch readTrailerMetadataResult(fromDevicePath: device.rawDevicePath, deviceSize: device.size) {
        case .metadata(let metadata):
            return .identified(ResolvedDeviceIdentity(metadata: metadata, source: .trailer))
        case .permissionDenied:
            return .trailerRequiresSudo
        case .notPresent:
            return .unassigned
        }
    }

    public func ensureDeviceIdentity(for device: DiskCandidate) -> ResolvedDeviceIdentity? {
        ensureDeviceIdentityStatus(for: device).resolvedIdentity
    }

    public func ensureDeviceIdentityStatus(for device: DiskCandidate) -> DeviceIdentityStatus {
        let existingStatus = resolveIdentityStatus(for: device)
        switch existingStatus {
        case .identified, .trailerRequiresSudo:
            return existingStatus
        case .unassigned:
            break
        }

        let metadata = FlashUUIDMetadata(
            flashUUID: nil,
            deviceUUID: UUID().uuidString,
            deviceName: device.displayName,
            imagePath: "",
            imageName: "",
            imageSHA256: nil,
            flashedAt: Date()
        )

        guard writeFileMetadata(metadata, to: device.partitions) else {
            return .unassigned
        }
        return .identified(ResolvedDeviceIdentity(metadata: metadata, source: .created))
    }

    public func readTrailerMetadata(fromDevicePath devicePath: String, deviceSize: Int64) -> FlashUUIDMetadata? {
        switch readTrailerMetadataResult(fromDevicePath: devicePath, deviceSize: deviceSize) {
        case .metadata(let metadata):
            return metadata
        case .notPresent, .permissionDenied:
            return nil
        }
    }

    func readTrailerMetadataResult(fromDevicePath devicePath: String, deviceSize: Int64) -> TrailerMetadataReadResult {
        guard deviceSize >= Int64(Self.trailerBlockSize) else {
            return .notPresent
        }

        let fd = open(devicePath, O_RDONLY)
        guard fd >= 0 else {
            if errno == EACCES || errno == EPERM {
                return .permissionDenied
            }
            return .notPresent
        }
        defer { close(fd) }

        let offset = off_t(deviceSize - Int64(Self.trailerBlockSize))
        var buffer = [UInt8](repeating: 0, count: Self.trailerBlockSize)
        let bytesRead = pread(fd, &buffer, Self.trailerBlockSize, offset)
        guard bytesRead > 0 else {
            if bytesRead < 0, errno == EACCES || errno == EPERM {
                return .permissionDenied
            }
            return .notPresent
        }

        let data = Data(buffer.prefix(Int(bytesRead)))
        guard data.starts(with: Data(Self.trailerMagic.utf8)) else {
            return .notPresent
        }

        let payload = data.dropFirst(Self.trailerMagic.utf8.count)
        let trimmed = payload.prefix { $0 != 0 }
        guard !trimmed.isEmpty else {
            return .notPresent
        }

        guard let metadata = try? JSONCoding.decoder.decode(FlashUUIDMetadata.self, from: Data(trimmed)) else {
            return .notPresent
        }
        return .metadata(metadata)
    }

    public func writeMetadata(
        _ metadata: FlashUUIDMetadata,
        imageSize: Int64,
        to device: DiskCandidate,
        mountedPartitions: [PartitionVolume]
    ) -> MetadataWriteResult {
        let fileWritten = writeFileMetadata(metadata, to: mountedPartitions)
        let trailerWritten = writeTrailerMetadata(
            metadata,
            imageSize: imageSize,
            toDevicePath: device.rawDevicePath,
            deviceSize: device.size
        )
        return MetadataWriteResult(fileWritten: fileWritten, trailerWritten: trailerWritten)
    }

    private func writeFileMetadata(
        _ metadata: FlashUUIDMetadata,
        to partitions: [PartitionVolume]
    ) -> Bool {
        guard let target = partitions.first(where: { ($0.mountPoint?.isEmpty == false) && $0.isWritable }),
              let mountPoint = target.mountPoint
        else {
            return false
        }

        let url = URL(fileURLWithPath: mountPoint).appendingPathComponent(".uuid")
        do {
            let data = try JSONCoding.encoder.encode(metadata)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func writeTrailerMetadata(
        _ metadata: FlashUUIDMetadata,
        imageSize: Int64,
        toDevicePath devicePath: String,
        deviceSize: Int64
    ) -> Bool {
        let slack = deviceSize - imageSize
        guard slack >= Int64(Self.minimumTrailerSlack),
              deviceSize >= Int64(Self.trailerBlockSize)
        else {
            return false
        }

        guard let payload = try? JSONCoding.encoder.encode(metadata) else {
            return false
        }

        let maxPayloadSize = Self.trailerBlockSize - Self.trailerMagic.utf8.count
        guard payload.count <= maxPayloadSize else {
            return false
        }

        var block = Data(count: Self.trailerBlockSize)
        block.replaceSubrange(0..<Self.trailerMagic.utf8.count, with: Data(Self.trailerMagic.utf8))
        let payloadStart = Self.trailerMagic.utf8.count
        block.replaceSubrange(payloadStart..<(payloadStart + payload.count), with: payload)

        let fd = open(devicePath, O_WRONLY)
        guard fd >= 0 else {
            return false
        }
        defer { close(fd) }

        let offset = off_t(deviceSize - Int64(Self.trailerBlockSize))
        let bytesWritten = block.withUnsafeBytes { rawBuffer in
            pwrite(fd, rawBuffer.baseAddress, Self.trailerBlockSize, offset)
        }
        guard bytesWritten == Self.trailerBlockSize else {
            return false
        }

        if fsync(fd) != 0 {
            return false
        }

        #if os(macOS)
        _ = fcntl(fd, F_FULLFSYNC)
        #endif
        return true
    }
}
