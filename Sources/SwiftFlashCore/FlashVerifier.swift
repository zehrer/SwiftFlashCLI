import Darwin
import Foundation

public protocol RawImageVerifying {
    func verifyImage(
        from imageURL: URL,
        to devicePath: String,
        progress: @escaping @Sendable (Double) -> Void
    ) throws
}

public final class FlashVerifier: RawImageVerifying {
    public init() {}

    public func verifyImage(
        from imageURL: URL,
        to devicePath: String,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        let inputFD = open(imageURL.path, O_RDONLY)
        guard inputFD >= 0 else {
            throw FlashError.ioFailed(String(cString: strerror(errno)))
        }
        defer { close(inputFD) }

        let deviceFD = open(devicePath, O_RDONLY)
        guard deviceFD >= 0 else {
            throw FlashError.verificationFailed(String(cString: strerror(errno)))
        }
        defer { close(deviceFD) }

        let totalBytes = try fileSize(of: inputFD)
        try Self.compareData(
            totalBytes: totalBytes,
            reader: { fd, buffer, count in read(fd, buffer, count) },
            imageFD: inputFD,
            deviceFD: deviceFD,
            progress: progress
        )
    }

    private func fileSize(of fd: Int32) throws -> Int64 {
        var statInfo = stat()
        guard fstat(fd, &statInfo) == 0 else {
            throw FlashError.ioFailed(String(cString: strerror(errno)))
        }
        return statInfo.st_size
    }

    static func compareData(
        totalBytes: Int64,
        reader: (Int32, UnsafeMutableRawPointer, Int) -> Int,
        imageFD: Int32,
        deviceFD: Int32,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        let chunkSize = 4 * 1024 * 1024
        let imageBuffer = UnsafeMutableRawPointer.allocate(byteCount: chunkSize, alignment: 4096)
        let deviceBuffer = UnsafeMutableRawPointer.allocate(byteCount: chunkSize, alignment: 4096)
        defer {
            imageBuffer.deallocate()
            deviceBuffer.deallocate()
        }

        var comparedBytes: Int64 = 0
        while true {
            let imageBytesRead = reader(imageFD, imageBuffer, chunkSize)
            if imageBytesRead < 0 {
                throw FlashError.ioFailed(String(cString: strerror(errno)))
            }
            if imageBytesRead == 0 {
                break
            }

            let deviceBytesRead = reader(deviceFD, deviceBuffer, imageBytesRead)
            if deviceBytesRead < 0 {
                throw FlashError.verificationFailed(String(cString: strerror(errno)))
            }
            if deviceBytesRead != imageBytesRead {
                throw FlashError.verificationFailed(
                    "short read at offset \(comparedBytes)"
                )
            }

            if memcmp(imageBuffer, deviceBuffer, imageBytesRead) != 0 {
                if let mismatchOffset = firstMismatchOffset(
                    imageBuffer: imageBuffer.assumingMemoryBound(to: UInt8.self),
                    deviceBuffer: deviceBuffer.assumingMemoryBound(to: UInt8.self),
                    count: imageBytesRead
                ) {
                    throw FlashError.verificationFailed(
                        "data mismatch at offset \(comparedBytes + Int64(mismatchOffset))"
                    )
                }
                throw FlashError.verificationFailed("data mismatch at offset \(comparedBytes)")
            }

            comparedBytes += Int64(imageBytesRead)
            if totalBytes > 0 {
                progress(min(Double(comparedBytes) / Double(totalBytes), 1.0))
            }
        }
    }

    private static func firstMismatchOffset(
        imageBuffer: UnsafePointer<UInt8>,
        deviceBuffer: UnsafePointer<UInt8>,
        count: Int
    ) -> Int? {
        for index in 0..<count where imageBuffer[index] != deviceBuffer[index] {
            return index
        }
        return nil
    }
}
