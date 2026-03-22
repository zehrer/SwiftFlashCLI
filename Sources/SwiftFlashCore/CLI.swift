import Foundation

public enum CLIParser {
    public static func parse(arguments: [String]) throws -> FlashCommand {
        let args = Array(arguments.dropFirst())
        guard let first = args.first else {
            return .flash(imagePath: nil, devicePath: nil, skipConfirmation: false)
        }

        switch first {
        case "flash":
            return try parseFlashArguments(Array(args.dropFirst()))
        case "verify":
            return try parseVerifyArguments(Array(args.dropFirst()))
        case "images":
            return .images
        case "devices":
            return try parseDevicesArguments(Array(args.dropFirst()))
        case "history":
            return try parseHistoryArguments(Array(args.dropFirst()))
        case "help", "--help", "-h":
            return .help
        default:
            return try parseFlashArguments(args)
        }
    }

    private static func parseDevicesArguments(_ args: [String]) throws -> FlashCommand {
        guard let subcommand = args.first else {
            return .devicesConnected
        }
        switch subcommand {
        case "connected":
            return .devicesConnected
        case "known":
            return .devicesKnown
        case "name":
            guard args.count >= 3 else {
                throw FlashError.usage("Usage: swiftflash devices name <device-uuid> <name>")
            }
            return .deviceName(id: args[1], name: args[2...].joined(separator: " "))
        case "clear-name":
            guard args.count == 2 else {
                throw FlashError.usage("Usage: swiftflash devices clear-name <device-uuid>")
            }
            return .deviceClearName(id: args[1])
        default:
            throw FlashError.usage("Unknown devices subcommand: \(subcommand)")
        }
    }

    private static func parseFlashArguments(_ args: [String]) throws -> FlashCommand {
        let skipConfirmation = args.contains("--yes")
        let positional = args.filter { $0 != "--yes" }
        guard positional.count <= 2 else {
            throw FlashError.usage("Usage: swiftflash [image_file] [/dev/diskX]")
        }

        let (imagePath, devicePath) = parseImageAndDeviceArguments(positional)
        return .flash(imagePath: imagePath, devicePath: devicePath, skipConfirmation: skipConfirmation)
    }

    private static func parseHistoryArguments(_ args: [String]) throws -> FlashCommand {
        guard let subcommand = args.first else {
            return .history
        }

        switch subcommand {
        case "clear":
            guard args.count == 1 else {
                throw FlashError.usage("Usage: swiftflash history clear")
            }
            return .historyClear
        default:
            throw FlashError.usage("Unknown history subcommand: \(subcommand)")
        }
    }

    private static func parseVerifyArguments(_ args: [String]) throws -> FlashCommand {
        guard args.count <= 2 else {
            throw FlashError.usage("Usage: swiftflash verify [image_file] [/dev/diskX]")
        }

        let (imagePath, devicePath) = parseImageAndDeviceArguments(args)
        return .verify(imagePath: imagePath, devicePath: devicePath)
    }

    private static func parseImageAndDeviceArguments(_ positional: [String]) -> (String?, String?) {
        var imagePath: String?
        var devicePath: String?

        switch positional.count {
        case 0:
            break
        case 1:
            if positional[0].hasPrefix("/dev/") {
                devicePath = positional[0]
            } else {
                imagePath = positional[0]
            }
        case 2:
            let first = positional[0]
            let second = positional[1]
            if first.hasPrefix("/dev/"), !second.hasPrefix("/dev/") {
                devicePath = first
                imagePath = second
            } else {
                imagePath = first
                devicePath = second
            }
        default:
            break
        }

        return (imagePath, devicePath)
    }
}

public struct HelpRenderer {
    public static let text = """
    SwiftFlashCLI

    Flash an image to an external physical drive:
      sudo swiftflash [image_file] [/dev/diskX]
      sudo swiftflash flash [image_file] [/dev/diskX] [--yes]

    Verify a flashed image against a raw device:
      sudo swiftflash verify [image_file] [/dev/diskX]

    List remembered images:
      swiftflash images

    List currently connected eligible flash devices:
      swiftflash devices
      swiftflash devices connected

    List remembered device inventory:
      swiftflash devices known

    Set or clear a custom name for a remembered device UUID:
      swiftflash devices name <device-uuid> <name>
      swiftflash devices clear-name <device-uuid>

    Show flash history:
      swiftflash history
      swiftflash history clear

    Typical flow:
      1. Run `swiftflash devices` to see connected target drives.
      2. Run `sudo swiftflash /path/to/image.iso /dev/diskX` to flash directly.
      3. Or run `sudo swiftflash` and select the image and device interactively.
      4. At the end of the write phase, choose whether to verify before metadata is written.

    Notes:
      - Flashing requires root privileges.
      - Verification also requires root privileges.
      - Only external physical whole disks are eligible targets.
      - `swiftflash devices` shows connected devices, not just remembered ones.
      - Writable new devices can receive a `device-uuid` immediately on scan.
      - `swiftflash devices` shows whether the `device-uuid` was reused from `.uuid`, reused from the trailer, or newly created.
    """
}
