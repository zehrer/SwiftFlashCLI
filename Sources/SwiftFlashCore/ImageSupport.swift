import CryptoKit
import Foundation

public enum ImageSupport {
    public static let supportedExtensions: Set<String> = ["iso", "img"]

    public static func validateImage(at path: String) throws -> ImageDescriptor {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FlashError.imageNotFound(url.path)
        }

        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw FlashError.invalidImage("Unsupported image format: .\(ext)")
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? NSNumber else {
            throw FlashError.invalidImage("Could not determine image size")
        }

        let size = fileSize.int64Value
        guard size >= 1024 * 1024 else {
            throw FlashError.invalidImage("Image file is too small to be valid")
        }

        return ImageDescriptor(url: url, size: size, checksum: nil)
    }

    public static func calculateSHA256(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func detectPartitionScheme(fileURL: URL) throws -> PartitionScheme {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        try handle.seek(toOffset: 0)
        let data = try handle.read(upToCount: 1024) ?? Data()
        guard data.count >= 1024 else {
            return .unknown
        }

        let mbr = data[0..<512]
        let gptHeader = data[512..<520]

        if mbr[510] == 0x55 && mbr[511] == 0xAA {
            if mbr[450] == 0xEE {
                return .gpt
            }
            return .mbr
        }

        if String(bytes: gptHeader, encoding: .ascii) == "EFI PART" {
            return .gpt
        }

        return .unknown
    }
}
