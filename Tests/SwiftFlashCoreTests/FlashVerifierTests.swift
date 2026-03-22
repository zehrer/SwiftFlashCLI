import Foundation
import Testing
@testable import SwiftFlashCore

struct FlashVerifierTests {
    @Test
    func compareDataPassesForMatchingBuffers() throws {
        let chunk = Array("abcdef".utf8)
        let box = ReaderBox(
            imageReads: [Data(chunk), Data()],
            deviceReads: [Data(chunk), Data()]
        )

        try FlashVerifier.compareData(
            totalBytes: Int64(chunk.count),
            reader: { fd, buffer, _ in
                let next = box.nextRead(for: fd)
                next.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: next.count)
                return next.count
            },
            imageFD: 1,
            deviceFD: 2,
            progress: { _ in }
        )
    }

    @Test
    func compareDataFailsForMismatch() throws {
        let image = Array("abcdef".utf8)
        let device = Array("abcxef".utf8)
        let box = ReaderBox(
            imageReads: [Data(image), Data()],
            deviceReads: [Data(device), Data()]
        )

        #expect(throws: FlashError.self) {
            try FlashVerifier.compareData(
                totalBytes: Int64(image.count),
                reader: { fd, buffer, _ in
                    let next = box.nextRead(for: fd)
                    next.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: next.count)
                    return next.count
                },
                imageFD: 1,
                deviceFD: 2,
                progress: { _ in }
            )
        }
    }
}

private final class ReaderBox {
    var imageReads: [Data]
    var deviceReads: [Data]

    init(imageReads: [Data], deviceReads: [Data]) {
        self.imageReads = imageReads
        self.deviceReads = deviceReads
    }

    func nextRead(for fd: Int32) -> Data {
        if fd == 1 {
            return imageReads.removeFirst()
        }
        return deviceReads.removeFirst()
    }
}
