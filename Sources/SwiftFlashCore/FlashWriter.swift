import Darwin
import Foundation

public protocol RawImageWriting {
    func writeImage(
        from imageURL: URL,
        to devicePath: String,
        progress: @escaping @Sendable (Double) -> Void
    ) throws
}

public final class FlashWriter: RawImageWriting {
    public init() {}

    public func writeImage(
        from imageURL: URL,
        to devicePath: String,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        let inputFD = open(imageURL.path, O_RDONLY)
        guard inputFD >= 0 else {
            throw FlashError.ioFailed(String(cString: strerror(errno)))
        }
        defer { close(inputFD) }

        let outputFD = open(devicePath, O_WRONLY)
        guard outputFD >= 0 else {
            throw FlashError.rawWriteFailed(String(cString: strerror(errno)))
        }
        defer { close(outputFD) }

        let totalSize = try fileSize(of: inputFD)
        try Self.copyData(
            totalBytes: totalSize,
            reader: { fd, buffer, count in read(fd, buffer, count) },
            writer: { fd, buffer, count in write(fd, buffer, count) },
            inputFD: inputFD,
            outputFD: outputFD,
            progress: progress
        )

        if fsync(outputFD) != 0 {
            throw FlashError.rawWriteFailed(String(cString: strerror(errno)))
        }

        #if os(macOS)
        _ = fcntl(outputFD, F_FULLFSYNC)
        #endif
    }

    private func fileSize(of fd: Int32) throws -> Int64 {
        var statInfo = stat()
        guard fstat(fd, &statInfo) == 0 else {
            throw FlashError.ioFailed(String(cString: strerror(errno)))
        }
        return statInfo.st_size
    }

    static func copyData(
        totalBytes: Int64,
        reader: (Int32, UnsafeMutableRawPointer, Int) -> Int,
        writer: (Int32, UnsafeRawPointer, Int) -> Int,
        inputFD: Int32,
        outputFD: Int32,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        let chunkSize = 4 * 1024 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunkSize, alignment: 4096)
        defer { buffer.deallocate() }

        var bytesWrittenTotal: Int64 = 0
        while true {
            let bytesRead = reader(inputFD, buffer, chunkSize)
            if bytesRead < 0 {
                throw FlashError.ioFailed(String(cString: strerror(errno)))
            }
            if bytesRead == 0 {
                break
            }

            try writeAll(
                data: buffer,
                byteCount: bytesRead,
                outputFD: outputFD,
                writer: writer
            )
            bytesWrittenTotal += Int64(bytesRead)
            if totalBytes > 0 {
                progress(min(Double(bytesWrittenTotal) / Double(totalBytes), 1.0))
            }
        }
    }

    static func writeAll(
        data: UnsafeMutableRawPointer,
        byteCount: Int,
        outputFD: Int32,
        writer: (Int32, UnsafeRawPointer, Int) -> Int
    ) throws {
        var remaining = byteCount
        var offset = 0
        while remaining > 0 {
            let pointer = data.advanced(by: offset)
            let written = writer(outputFD, pointer, remaining)
            if written < 0 {
                throw FlashError.rawWriteFailed(String(cString: strerror(errno)))
            }
            remaining -= written
            offset += written
        }
    }
}
