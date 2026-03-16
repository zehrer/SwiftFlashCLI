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
        case "images":
            return .images
        case "devices":
            return try parseDevicesArguments(Array(args.dropFirst()))
        case "history":
            return .history
        case "help", "--help", "-h":
            return .help
        default:
            return try parseFlashArguments(args)
        }
    }

    private static func parseDevicesArguments(_ args: [String]) throws -> FlashCommand {
        guard let subcommand = args.first else {
            return .devices
        }
        switch subcommand {
        case "name":
            guard args.count >= 3 else {
                throw FlashError.usage("Usage: swiftflash devices name <physical-device-id> <name>")
            }
            return .deviceName(id: args[1], name: args[2...].joined(separator: " "))
        case "clear-name":
            guard args.count == 2 else {
                throw FlashError.usage("Usage: swiftflash devices clear-name <physical-device-id>")
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

        return .flash(imagePath: imagePath, devicePath: devicePath, skipConfirmation: skipConfirmation)
    }
}

public struct HelpRenderer {
    public static let text = """
    swiftflash [image_file] [/dev/diskX]
    swiftflash flash [image_file] [/dev/diskX] [--yes]
    swiftflash images
    swiftflash devices
    swiftflash devices name <physical-device-id> <name>
    swiftflash devices clear-name <physical-device-id>
    swiftflash history
    """
}
