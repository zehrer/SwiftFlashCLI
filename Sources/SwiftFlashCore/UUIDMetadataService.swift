import Foundation

public final class UUIDMetadataService {
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

    public func writeMetadata(
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
}
