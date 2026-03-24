import Foundation
import SwiftFlashCore

@main
struct SwiftFlashCLI {
    static func main() async {
        let services: Services
        do {
            let configStore = try AppConfigStore()
            services = Services(
                imageStore: ImageCatalogStore(configStore: configStore),
                deviceStore: DeviceInventoryStore(configStore: configStore),
                historyStore: FlashHistoryStore(configStore: configStore),
                scanner: DeviceScanner(),
                deviceManager: DiskArbitrationManager(),
                prompt: PromptRenderer(),
                uuidService: UUIDMetadataService()
            )
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }

        do {
            let command = try CLIParser.parse(arguments: CommandLine.arguments)
            try await execute(command: command, services: services)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func execute(command: FlashCommand, services: Services) async throws {
        switch command {
            case .repl:
                try await runREPL(services: services)

            case .flash(let imagePath, let devicePath, let skipConfirmation):
                guard geteuid() == 0 else {
                    throw FlashError.requiresRoot
                }

                let image = try resolveImage(path: imagePath, imageStore: services.imageStore, prompt: services.prompt)
                let device = try resolveDevice(path: devicePath, scanner: services.scanner, prompt: services.prompt)
                if !skipConfirmation && !services.prompt.confirmFlash(image: image, device: device) {
                    throw FlashError.cancelled
                }

                print("Flashing \(image.name) to \(device.displayName) (\(device.devicePath))")
                let writeProgress = ConsoleProgressRenderer(label: "Flash", totalBytes: image.size)
                let verifyProgress = ConsoleProgressRenderer(label: "Verify", totalBytes: image.size)
                let prompt = services.prompt
                let completion = try await services.flashService.flash(
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

                let image = try resolveImage(path: imagePath, imageStore: services.imageStore, prompt: services.prompt)
                let device = try resolveDevice(path: devicePath, scanner: services.scanner, prompt: services.prompt)
                let verifyProgress = ConsoleProgressRenderer(label: "Verify", totalBytes: image.size)
                print("Verifying \(image.name) against \(device.displayName) (\(device.devicePath))")
                try await services.flashService.verify(
                    image: image,
                    device: device,
                    progress: { progress in
                        verifyProgress.update(progress: progress)
                    }
                )
                verifyProgress.finish(status: "Verification complete")
                print("Verification successful")

            case .images:
                let images = services.imageStore.allImages()
                if images.isEmpty {
                    print("No remembered images")
                } else {
                    for image in images {
                        print("\(image.displayName)\t\(image.path)")
                    }
                }

            case .mediaList:
                try listConnectedMedia(
                    scanner: services.scanner,
                    uuidService: services.uuidService,
                    deviceStore: services.deviceStore,
                    identifyNewMedia: false
                )

            case .mediaKnown:
                let media = services.deviceStore.allDevices()
                if media.isEmpty {
                    print("No remembered media")
                } else {
                    for medium in media {
                        let mediaType = medium.mediaTypeName ?? "-"
                        print("\(medium.displayName)\t\(medium.deviceUUID)\t\(mediaType)")
                    }
                }

            case .mediaInfo(let query):
                try showMediaInfo(
                    query: query,
                    scanner: services.scanner,
                    uuidService: services.uuidService,
                    deviceStore: services.deviceStore
                )

            case .mediaIdentify:
                try listConnectedMedia(
                    scanner: services.scanner,
                    uuidService: services.uuidService,
                    deviceStore: services.deviceStore,
                    identifyNewMedia: true
                )

            case .mediaTypes:
                let mediaTypes = services.deviceStore.allMediaTypes()
                if mediaTypes.isEmpty {
                    print("No configured media types")
                } else {
                    for mediaType in mediaTypes {
                        let source = mediaType.isPreconfigured ? "preconfigured" : "custom"
                        print("\(mediaType.name)\t\(source)")
                    }
                }

            case .mediaTypeAdd(let name):
                try services.deviceStore.addMediaType(name: name)
                print("Added media type")

            case .mediaSetType(let id, let typeName):
                try services.deviceStore.setMediaType(id: id, mediaTypeName: typeName)
                print("Updated media type")

            case .mediaClearType(let id):
                try services.deviceStore.setMediaType(id: id, mediaTypeName: nil)
                print("Cleared media type")

            case .mediaName(let id, let name):
                try services.deviceStore.setCustomName(id: id, name: name)
                print("Updated media name")

            case .mediaClearName(let id):
                try services.deviceStore.setCustomName(id: id, name: nil)
                print("Cleared media name")

            case .history:
                let history = services.historyStore.allHistory()
                if history.isEmpty {
                    print("No flash history")
                } else {
                    for entry in history {
                        print("\(entry.finishedAt.ISO8601Format())\t\(entry.imageName)\t\(entry.deviceUUID)\t\(entry.result)")
                    }
                }

            case .historyClear:
                try services.historyStore.clear()
                print("Cleared flash history")

            case .help:
                print(HelpRenderer.text)
        }
    }

    private static func runREPL(services: Services) async throws {
        print("SwiftFlashCLI interactive shell")
        print("Type `help` for commands. Type `exit`, `quit`, or `quite` to leave.")

        while true {
            print("swiftflash> ", terminator: "")
            fflush(stdout)

            guard let line = readLine(strippingNewline: true) else {
                print("")
                break
            }

            do {
                switch try CLIParser.parseInteractive(line: line) {
                case .empty:
                    continue
                case .exit:
                    return
                case .command(let command):
                    try await execute(command: command, services: services)
                }
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
            }
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

    private static func listConnectedMedia(
        scanner: DeviceScanner,
        uuidService: UUIDMetadataService,
        deviceStore: DeviceInventoryStore,
        identifyNewMedia: Bool
    ) throws {
        let scanned = try scanner.scanEligibleDevices()
        if scanned.isEmpty {
            print("No connected eligible flash media")
            return
        }

        let knownByID = Dictionary(uniqueKeysWithValues: deviceStore.allDevices().map { ($0.deviceUUID, $0) })
        for device in scanned {
            let identity = identifyNewMedia
                ? uuidService.ensureDeviceIdentity(for: device)
                : uuidService.resolveIdentity(for: device)
            let metadata = identity?.metadata
            let known = metadata.flatMap { knownByID[$0.deviceUUID] }
            let displayName = known?.displayName ?? device.displayName
            let deviceIdentifier = metadata?.deviceUUID ?? "unassigned"
            let mediaType = known?.mediaTypeName ?? "-"
            let rememberedSuffix = known == nil ? "" : " [remembered]"
            let source = identity?.source.displayLabel ?? "unassigned"
            if let metadata {
                try? deviceStore.upsert(deviceUUID: metadata.deviceUUID, candidate: device)
            }
            print(
                "\(displayName)\t\(device.devicePath)\t\(device.formattedSize)\t\(deviceIdentifier)\ttype:\(mediaType)\tdevice-uuid:\(source)\(rememberedSuffix)"
            )
        }
    }

    private static func showMediaInfo(
        query: String,
        scanner: DeviceScanner,
        uuidService: UUIDMetadataService,
        deviceStore: DeviceInventoryStore
    ) throws {
        guard let medium = deviceStore.findDevice(matching: query) else {
            throw FlashError.usage("No remembered medium found for: \(query)")
        }

        let connectedDevice = try scanner.scanEligibleDevices().first { device in
            uuidService.resolveIdentity(for: device)?.metadata.deviceUUID == medium.deviceUUID
        }
        let connectedIdentity = connectedDevice.flatMap { uuidService.resolveIdentity(for: $0) }
        let customName = medium.customName ?? "-"
        let identification = connectedIdentity?.source.displayLabel ?? "unknown"
        let mediaType = medium.mediaTypeName ?? "-"

        print("Media: \(medium.displayName)")
        print("Device UUID: \(medium.deviceUUID)")
        print("Custom Name: \(customName)")
        print("Media Type: \(mediaType)")
        print("Size: \(ByteCountFormatter.string(fromByteCount: medium.size, countStyle: .file))")
        print("First Seen: \(medium.firstSeen.ISO8601Format())")
        print("Last Seen: \(medium.lastSeen.ISO8601Format())")
        if let connectedDevice {
            print("Connected: yes")
            print("Current Device: \(connectedDevice.devicePath)")
            print("Identification: \(identification)")
        } else {
            print("Connected: no")
        }
        if medium.userDefinedFields.isEmpty {
            print("User Fields: none")
        } else {
            print("User Fields:")
            for key in medium.userDefinedFields.keys.sorted() {
                if let value = medium.userDefinedFields[key] {
                    print("  \(key): \(value)")
                }
            }
        }
    }

    private struct Services {
        let imageStore: ImageCatalogStore
        let deviceStore: DeviceInventoryStore
        let historyStore: FlashHistoryStore
        let scanner: DeviceScanner
        let deviceManager: DiskArbitrationManager
        let prompt: PromptRenderer
        let uuidService: UUIDMetadataService

        var flashService: FlashService {
            FlashService(
                scanner: scanner,
                deviceManager: deviceManager,
                writer: FlashWriter(),
                verifier: FlashVerifier(),
                uuidService: uuidService,
                imageStore: imageStore,
                deviceStore: deviceStore,
                historyStore: historyStore
            )
        }
    }
}
