import Foundation

public final class PromptRenderer {
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

    public func selectDevice(from devices: [DiskCandidate]) throws -> DiskCandidate {
        guard !devices.isEmpty else {
            throw FlashError.noEligibleDevices
        }

        if devices.count == 1 {
            let device = devices[0]
            print("Use the only available device: \(device.displayName) (\(device.devicePath), \(device.formattedSize))? [Y/n]")
            let answer = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if answer == nil || answer == "" || answer == "y" || answer == "yes" {
                return device
            }
            throw FlashError.cancelled
        }

        print("Select a target device:")
        for (index, device) in devices.enumerated() {
            print("  \(index + 1)) \(device.displayName) [\(device.devicePath)] \(device.formattedSize)")
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

    public func confirmFlash(image: ImageDescriptor, device: DiskCandidate) -> Bool {
        print("About to erase \(device.displayName) (\(device.devicePath), \(device.formattedSize))")
        print("Image: \(image.url.path) (\(ByteCountFormatter.string(fromByteCount: image.size, countStyle: .file)))")
        print("Continue? [y/N]")
        let answer = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return answer == "y" || answer == "yes"
    }
}
