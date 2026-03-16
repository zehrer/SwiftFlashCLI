import Foundation
import SwiftFlashCore

@main
struct SwiftFlashCLI {
    static func main() async {
        do {
            let command = try CLIParser.parse(arguments: CommandLine.arguments)
            if case .help = command {
                print(HelpRenderer.text)
                return
            }

            let configStore = try AppConfigStore()
            let imageStore = ImageCatalogStore(configStore: configStore)
            let deviceStore = DeviceInventoryStore(configStore: configStore)
            let historyStore = FlashHistoryStore(configStore: configStore)
            let scanner = DeviceScanner()
            let deviceManager = DiskArbitrationManager()
            let prompt = PromptRenderer()
            let flashService = FlashService(
                scanner: scanner,
                deviceManager: deviceManager,
                writer: FlashWriter(),
                uuidService: UUIDMetadataService(),
                imageStore: imageStore,
                deviceStore: deviceStore,
                historyStore: historyStore
            )

            switch command {
            case .flash(let imagePath, let devicePath, let skipConfirmation):
                guard geteuid() == 0 else {
                    throw FlashError.requiresRoot
                }

                let image = try resolveImage(path: imagePath, imageStore: imageStore, prompt: prompt)
                let device = try resolveDevice(path: devicePath, scanner: scanner, prompt: prompt)
                if !skipConfirmation && !prompt.confirmFlash(image: image, device: device) {
                    throw FlashError.cancelled
                }

                print("Flashing \(image.name) to \(device.displayName) (\(device.devicePath))")
                try await flashService.flash(image: image, device: device) { progress in
                    let percent = Int(progress * 100.0)
                    print("Progress: \(percent)%")
                }
                print("Flash completed")

            case .images:
                let images = imageStore.allImages()
                if images.isEmpty {
                    print("No remembered images")
                } else {
                    for image in images {
                        print("\(image.displayName)\t\(image.path)")
                    }
                }

            case .devices:
                let devices = deviceStore.allDevices()
                if devices.isEmpty {
                    print("No remembered devices")
                } else {
                    for device in devices {
                        print("\(device.displayName)\t\(device.physicalDeviceID)")
                    }
                }

            case .deviceName(let id, let name):
                try deviceStore.setCustomName(id: id, name: name)
                print("Updated device name")

            case .deviceClearName(let id):
                try deviceStore.setCustomName(id: id, name: nil)
                print("Cleared device name")

            case .history:
                let history = historyStore.allHistory()
                if history.isEmpty {
                    print("No flash history")
                } else {
                    for entry in history {
                        print("\(entry.finishedAt.ISO8601Format())\t\(entry.imageName)\t\(entry.physicalDeviceID)\t\(entry.result)")
                    }
                }

            case .help:
                print(HelpRenderer.text)
            }
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func resolveImage(
        path: String?,
        imageStore: ImageCatalogStore,
        prompt: PromptRenderer
    ) throws -> ImageDescriptor {
        let resolvedPath = try path ?? prompt.selectImage(from: imageStore.allImages())
        return try ImageSupport.validateImage(at: resolvedPath)
    }

    private static func resolveDevice(
        path: String?,
        scanner: DeviceScanner,
        prompt: PromptRenderer
    ) throws -> DiskCandidate {
        if let path {
            if let device = try scanner.findEligibleDevice(at: path) {
                return device
            }
            throw FlashError.deviceNotFound(path)
        }
        let devices = try scanner.scanEligibleDevices()
        return try prompt.selectDevice(from: devices)
    }
}
