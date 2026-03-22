import Foundation

final class ConsoleProgressRenderer: @unchecked Sendable {
    private let label: String
    private let totalBytes: Int64
    private let barWidth = 28
    private let start = Date()
    private var hasRendered = false
    private var isFinished = false
    private var lastRenderTime = Date.distantPast

    init(label: String, totalBytes: Int64) {
        self.label = label
        self.totalBytes = totalBytes
    }

    func update(progress: Double) {
        guard !isFinished else { return }
        let now = Date()
        if hasRendered && progress < 1.0 && now.timeIntervalSince(lastRenderTime) < 0.1 {
            return
        }

        hasRendered = true
        lastRenderTime = now

        let clamped = min(max(progress, 0.0), 1.0)
        let completedBytes = Int64(Double(totalBytes) * clamped)
        let filled = Int(Double(barWidth) * clamped)
        let bar = String(repeating: "#", count: filled) + String(repeating: "-", count: max(0, barWidth - filled))
        let percent = Int(clamped * 100.0)
        let elapsed = max(now.timeIntervalSince(start), 0.001)
        let bytesPerSecond = Double(completedBytes) / elapsed

        let line = "\r\(label) [\(bar)] \(String(format: "%3d", percent))%  \(formatBytes(completedBytes))/\(formatBytes(totalBytes))  \(formatBytesPerSecond(bytesPerSecond))"
        FileHandle.standardOutput.write(Data(line.utf8))
    }

    func finish(status: String) {
        if !hasRendered || isFinished {
            return
        }
        let now = Date()
        let completedBytes = totalBytes
        let filled = barWidth
        let bar = String(repeating: "#", count: filled)
        let elapsed = max(now.timeIntervalSince(start), 0.001)
        let bytesPerSecond = Double(completedBytes) / elapsed
        let line = "\r\(label) [\(bar)] 100%  \(formatBytes(completedBytes))/\(formatBytes(totalBytes))  \(formatBytesPerSecond(bytesPerSecond))"
        FileHandle.standardOutput.write(Data(line.utf8))
        isFinished = true
        FileHandle.standardOutput.write(Data("  \(status)\n".utf8))
    }

    func finishIfStarted(status: String) {
        finish(status: status)
    }

    private func formatBytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    private func formatBytesPerSecond(_ value: Double) -> String {
        let intValue = Int64(value.rounded())
        return "\(ByteCountFormatter.string(fromByteCount: intValue, countStyle: .file))/s"
    }
}
