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
            let uuidService = UUIDMetadataService()
            let flashService = FlashService(
                scanner: scanner,
                deviceManager: deviceManager,
                writer: FlashWriter(),
                verifier: FlashVerifier(),
                uuidService: uuidService,
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
                let writeProgress = ConsoleProgressRenderer(label: "Flash", totalBytes: image.size)
                let verifyProgress = ConsoleProgressRenderer(label: "Verify", totalBytes: image.size)
                let completion = try await flashService.flash(
                    image: image,
                    device: device,
                    writeProgress: { progress in
                        writeProgress.update(progress: progress)
                    },
                    promptForVerification: {
                        writeProgress.finish(status: "Flash write complete")
                        return prompt.confirmVerifyAfterFlash()
                    },
                    verifyProgress: { progress in
                        verifyProgress.update(progress: progress)
                    }
                )
                writeProgress.finish(status: "Flash write complete")
                verifyProgress.finishIfStarted(status: "Verification complete")
                let deviceUUIDAction = completion.previousIdentity == nil ? "created and written" : "reused and written"
                print("Device UUID \(deviceUUIDAction): \(completion.metadata.deviceUUID)")
                if let flashUUID = completion.metadata.flashUUID {
                    print("Flash UUID written: \(flashUUID.uuidString)")
                }
                print("Metadata stored in: \(completion.writeResult.storageDescription)")
                print("Flash completed")

            case .verify(let imagePath, let devicePath):
                guard geteuid() == 0 else {
                    throw FlashError.requiresRoot
                }

                let image = try resolveImage(path: imagePath, imageStore: imageStore, prompt: prompt)
                let device = try resolveDevice(path: devicePath, scanner: scanner, prompt: prompt)
                let verifyProgress = ConsoleProgressRenderer(label: "Verify", totalBytes: image.size)
                print("Verifying \(image.name) against \(device.displayName) (\(device.devicePath))")
                try await flashService.verify(
                    image: image,
                    device: device,
                    progress: { progress in
                        verifyProgress.update(progress: progress)
                    }
                )
                verifyProgress.finish(status: "Verification complete")
                print("Verification successful")

            case .images:
                let images = imageStore.allImages()
                if images.isEmpty {
                    print("No remembered images")
                } else {
                    for image in images {
                        print("\(image.displayName)\t\(image.path)")
                    }
                }

            case .devicesConnected:
                let scanned = try scanner.scanEligibleDevices()
                if scanned.isEmpty {
                    print("No connected eligible flash devices")
                } else {
                    let knownByID = Dictionary(
                        uniqueKeysWithValues: deviceStore.allDevices().map { ($0.deviceUUID, $0) }
                    )
                    for device in scanned {
                        let identity = uuidService.ensureDeviceIdentity(for: device)
                        let metadata = identity?.metadata
                        let known = metadata.flatMap { knownByID[$0.deviceUUID] }
                        let displayName = known?.displayName ?? device.displayName
                        let deviceIdentifier = metadata?.deviceUUID ?? "unassigned"
                        let rememberedSuffix = known == nil ? "" : " [remembered]"
                        let source = identity?.source.displayLabel ?? "unassigned"
                        if let metadata {
                            try? deviceStore.upsert(deviceUUID: metadata.deviceUUID, candidate: device)
                        }
                        print(
                            "\(displayName)\t\(device.devicePath)\t\(device.formattedSize)\t\(deviceIdentifier)\tdevice-uuid:\(source)\(rememberedSuffix)"
                        )
                    }
                }

            case .devicesKnown:
                let devices = deviceStore.allDevices()
                if devices.isEmpty {
                    print("No remembered devices")
                } else {
                    for device in devices {
                        print("\(device.displayName)\t\(device.deviceUUID)")
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
                        print("\(entry.finishedAt.ISO8601Format())\t\(entry.imageName)\t\(entry.deviceUUID)\t\(entry.result)")
                    }
                }

            case .historyClear:
                try historyStore.clear()
                print("Cleared flash history")

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
