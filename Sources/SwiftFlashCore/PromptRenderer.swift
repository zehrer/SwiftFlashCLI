import Foundation

public final class PromptRenderer: @unchecked Sendable {
    public init() {}

    public func selectImage(from images: [RememberedImage]) throws -> String {
        if images.isEmpty {
            print("No remembered images. Enter a path to an image file:")
            guard let input = readLine(strippingNewline: true), !input.isEmpty else {
                throw FlashError.cancelled
            }
            return input
        }

        print("Select an image:")
        print("  0) Enter a new path")
        for (index, image) in images.enumerated() {
            print("  \(index + 1)) \(image.displayName) [\(image.path)]")
        }
        guard let line = readLine(strippingNewline: true),
              let selection = Int(line)
        else {
            throw FlashError.cancelled
        }
        if selection == 0 {
            print("Enter a path to an image file:")
            guard let input = readLine(strippingNewline: true), !input.isEmpty else {
                throw FlashError.cancelled
            }
            return input
        }
        let index = selection - 1
        guard images.indices.contains(index) else {
            throw FlashError.cancelled
        }
        return images[index].path
    }

    public func selectDevice(
        from devices: [DiskCandidate],
        overview: (DiskCandidate) -> DeviceOverview? = { _ in nil }
    ) throws -> DiskCandidate {
        guard !devices.isEmpty else {
            throw FlashError.noEligibleDevices
        }

        if devices.count == 1 {
            let device = devices[0]
            let info = overview(device)
            let title = info?.title ?? device.displayName
            print("Use the only available device: \(title) (\(device.devicePath), \(device.formattedSize))? [Y/n]")
            printDetails(info)
            let answer = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if answer == nil || answer == "" || answer == "y" || answer == "yes" {
                return device
            }
            throw FlashError.cancelled
        }

        print("Select a target device:")
        for (index, device) in devices.enumerated() {
            let info = overview(device)
            print("  \(index + 1)) \(info?.title ?? device.displayName) [\(device.devicePath)] \(device.formattedSize)")
            printDetails(info, indent: "       ")
        }

        guard let line = readLine(strippingNewline: true), let selection = Int(line) else {
            throw FlashError.cancelled
        }
        let index = selection - 1
        guard devices.indices.contains(index) else {
            throw FlashError.cancelled
        }
        return devices[index]
    }

    public func confirmFlash(image: ImageDescriptor, device: DiskCandidate, overview: DeviceOverview? = nil) -> Bool {
        print("About to erase \(overview?.title ?? device.displayName) (\(device.devicePath), \(device.formattedSize))")
        if let currentContent = overview?.currentContent {
            print("Replaces: \(currentContent)")
        }
        print("Image: \(image.sourcePath) (\(ByteCountFormatter.string(fromByteCount: image.size, countStyle: .file)))")
        print("Continue? [y/N]")
        let answer = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return answer == "y" || answer == "yes"
    }

    private func printDetails(_ overview: DeviceOverview?, indent: String = "  ") {
        for line in overview?.details ?? [] {
            print("\(indent)\(line)")
        }
    }

    public func confirmVerifyAfterFlash() -> Bool {
        print("Flash write complete. Verify the flashed image now before metadata is written? [y/N]")
        let answer = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return answer == "y" || answer == "yes"
    }
}
