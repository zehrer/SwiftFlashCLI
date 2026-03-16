import Foundation
import Testing
@testable import SwiftFlashCore

struct FlashWriterTests {
    @Test
    func writeAllHandlesShortWrites() throws {
        var buffer = Array("abcdef".utf8)
        var writes: [Int] = [2, 2, 2]
        var output = Data()

        try FlashWriter.writeAll(
            data: &buffer,
            byteCount: buffer.count,
            outputFD: 1,
            writer: { _, pointer, remaining in
                let next = writes.removeFirst()
                output.append(pointer.assumingMemoryBound(to: UInt8.self), count: min(next, remaining))
                return min(next, remaining)
            }
        )

        #expect(String(data: output, encoding: .utf8) == "abcdef")
    }

    @Test
    func partitionSchemeDetectorRecognizesGPT() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var bytes = Data(repeating: 0, count: 1024)
        bytes[510] = 0x55
        bytes[511] = 0xAA
        bytes[450] = 0xEE
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let scheme = try ImageSupport.detectPartitionScheme(fileURL: url)
        #expect(scheme == .gpt)
    }
}
