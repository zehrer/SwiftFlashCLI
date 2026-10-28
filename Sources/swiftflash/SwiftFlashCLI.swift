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

                let prepared = try await resolveImage(path: imagePath, imageStore: services.imageStore, prompt: services.prompt)
                defer { cleanup(prepared) }
                let image = prepared.image
                let device = try resolveDevice(path: devicePath, services: services)
                if !skipConfirmation
                    && !services.prompt.confirmFlash(image: image, device: device, overview: overview(of: device, services: services)) {
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
                if let imageLabel = completion.metadata.image?.displayLabel {
                    print("Image identity kept: \(imageLabel)")
                }
                print("Metadata stored in: \(completion.writeResult.storageDescription)")
                print("Flash completed")

            case .verify(let imagePath, let devicePath):
                guard geteuid() == 0 else {
                    throw FlashError.requiresRoot
                }

                let prepared = try await resolveImage(path: imagePath, imageStore: services.imageStore, prompt: services.prompt)
                defer { cleanup(prepared) }
                let image = prepared.image
                let device = try resolveDevice(path: devicePath, services: services)
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

            case .imagesClear:
                try services.imageStore.clear()
                print("Cleared remembered images")

            case .imagesRemove(let query):
                let removed = try services.imageStore.remove(matching: query)
                guard removed > 0 else {
                    throw FlashError.usage("No remembered image found for: \(query)")
                }
                print(removed == 1 ? "Removed remembered image" : "Removed \(removed) remembered images")

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
                        let imageLabel = entry.image?.displayLabel ?? "-"
                        print("\(entry.finishedAt.ISO8601Format())\t\(entry.imageName)\t\(imageLabel)\t\(entry.deviceUUID)\t\(entry.result)")
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
    ) async throws -> PreparedImage {
        let resolvedPath = try path ?? prompt.selectImage(from: imageStore.allImages())
        let progress = PreparationProgress()
        let prepared = try await ImagePreparer().prepare(source: resolvedPath) { update in
            progress.update(update)
        }
        progress.finish()
        return prepared
    }

    private static func cleanup(_ prepared: PreparedImage) {
        guard prepared.hasTemporaryFiles else { return }
        prepared.cleanup()
        print("Removed temporary image files")
    }

    /// Shows one progress bar per preparation step (download, unpack) with the bytes downloaded or unpacked so far.
    private final class PreparationProgress: @unchecked Sendable {
        private let lock = NSLock()
        private var step: ImagePreparationStep?
        private var renderer: ConsoleProgressRenderer?

        func update(_ update: ImagePreparationProgress) {
            lock.lock()
            defer { lock.unlock() }
            if update.step != step {
                finishLocked()
                step = update.step
                let label = update.step == .download ? "Download" : "Unpack"
                renderer = ConsoleProgressRenderer(label: label, totalBytes: 0)
            }
            renderer?.update(progress: update.fraction, processedBytes: update.processedBytes)
        }

        func finish() {
            lock.lock()
            defer { lock.unlock() }
            finishLocked()
        }

        private func finishLocked() {
            switch step {
            case .download:
                renderer?.finish(status: "Download complete")
            case .decompress:
                renderer?.finish(status: "Unpack complete")
            case nil:
                break
            }
            renderer = nil
        }
    }

    private static func resolveDevice(path: String?, services: Services) throws -> DiskCandidate {
        if let path {
            if let device = try services.scanner.findEligibleDevice(at: path) {
                return device
            }
            throw FlashError.deviceNotFound(path)
        }
        let devices = try services.scanner.scanEligibleDevices()
        return try services.prompt.selectDevice(from: devices) { device in
            overview(of: device, services: services)
        }
    }

    /// Describes a target medium: remembered name and type, and the image currently on it.
    private static func overview(of device: DiskCandidate, services: Services) -> DeviceOverview {
        let status = services.uuidService.resolveIdentityStatus(for: device)
        let deviceUUID = status.resolvedIdentity?.metadata.deviceUUID
        let knownDevice = deviceUUID.flatMap { uuid in
            services.deviceStore.allDevices().first { $0.deviceUUID == uuid }
        }
        return DeviceOverview.make(
            device: device,
            identityStatus: status,
            knownDevice: knownDevice,
            imageIdentity: services.uuidService.readImageIdentity(from: device.partitions)
        )
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
            let identityStatus = identifyNewMedia
                ? uuidService.ensureDeviceIdentityStatus(for: device)
                : uuidService.resolveIdentityStatus(for: device)
            let metadata = identityStatus.resolvedIdentity?.metadata
            let known = metadata.flatMap { knownByID[$0.deviceUUID] }
            let displayName = known?.displayName ?? device.displayName
            let deviceIdentifier = identityStatus.deviceUUIDDisplay
            let mediaType = known?.mediaTypeName ?? "-"
            let rememberedSuffix = known == nil ? "" : " [remembered]"
            let source = identityStatus.sourceDisplay
            let imageLabel = (metadata?.image ?? uuidService.readImageIdentity(from: device.partitions))?.displayLabel ?? "-"
            if let metadata {
                try? deviceStore.upsert(deviceUUID: metadata.deviceUUID, candidate: device)
            }
            print(
                "\(displayName)\t\(device.devicePath)\t\(device.formattedSize)\t\(deviceIdentifier)\ttype:\(mediaType)\timage:\(imageLabel)\tdevice-uuid:\(source)\(rememberedSuffix)"
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

        let scannedDevices = try scanner.scanEligibleDevices()
        let statusByDevicePath = Dictionary(
            scannedDevices.map { ($0.devicePath, uuidService.resolveIdentityStatus(for: $0)) },
            uniquingKeysWith: { first, _ in first }
        )
        let connectedDevice = scannedDevices.first { device in
            statusByDevicePath[device.devicePath]?.resolvedIdentity?.metadata.deviceUUID == medium.deviceUUID
        }
        let connectedIdentityStatus = connectedDevice.flatMap { statusByDevicePath[$0.devicePath] }
        let customName = medium.customName ?? "-"
        let identification = connectedIdentityStatus?.sourceDisplay ?? "unknown"
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
            let image = connectedIdentityStatus?.resolvedIdentity?.metadata.image
            print("Image: \(image?.displayLabel ?? "-")")
            if let build = image?.build {
                print("Image Build: \(build)")
            }
        } else {
            print("Connected: no")
            if scannedDevices.contains(where: { statusByDevicePath[$0.devicePath] == .trailerRequiresSudo }) {
                print("Note: some connected media require sudo to inspect trailer metadata")
            }
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
