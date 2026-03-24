import Foundation

public enum CLIParser {
    public static func parse(arguments: [String]) throws -> FlashCommand {
        let args = Array(arguments.dropFirst())
        guard let first = args.first else {
            return .repl
        }

        switch first {
        case "flash":
            return try parseFlashArguments(Array(args.dropFirst()))
        case "verify":
            return try parseVerifyArguments(Array(args.dropFirst()))
        case "identify":
            return .mediaIdentify
        case "images":
            return .images
        case "media":
            return try parseMediaArguments(Array(args.dropFirst()))
        case "devices":
            return try parseLegacyDevicesArguments(Array(args.dropFirst()))
        case "history":
            return try parseHistoryArguments(Array(args.dropFirst()))
        case "help", "--help", "-h":
            return .help
        default:
            return try parseFlashArguments(args)
        }
    }

    public static func parseInteractive(line: String) throws -> InteractiveInput {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .empty
        }

        let tokens = try tokenize(line: trimmed)
        guard let first = tokens.first?.lowercased() else {
            return .empty
        }

        if ["exit", "quit", "quite"].contains(first), tokens.count == 1 {
            return .exit
        }

        return .command(try parse(arguments: ["swiftflash"] + tokens))
    }

    private static func parseMediaArguments(_ args: [String]) throws -> FlashCommand {
        guard let subcommand = args.first else {
            return .mediaList
        }
        switch subcommand {
        case "list", "connected":
            return .mediaList
        case "known":
            return .mediaKnown
        case "info":
            guard args.count >= 2 else {
                throw FlashError.usage("Usage: swiftflash media info <name-or-device-uuid>")
            }
            return .mediaInfo(query: args[1...].joined(separator: " "))
        case "identify":
            return .mediaIdentify
        case "types":
            return .mediaTypes
        case "type-add":
            guard args.count >= 2 else {
                throw FlashError.usage("Usage: swiftflash media type-add <type-name>")
            }
            return .mediaTypeAdd(name: args[1...].joined(separator: " "))
        case "set-type":
            guard args.count >= 3 else {
                throw FlashError.usage("Usage: swiftflash media set-type <device-uuid> <type-name>")
            }
            return .mediaSetType(id: args[1], typeName: args[2...].joined(separator: " "))
        case "clear-type":
            guard args.count == 2 else {
                throw FlashError.usage("Usage: swiftflash media clear-type <device-uuid>")
            }
            return .mediaClearType(id: args[1])
        case "name":
            guard args.count >= 3 else {
                throw FlashError.usage("Usage: swiftflash media name <device-uuid> <name>")
            }
            return .mediaName(id: args[1], name: args[2...].joined(separator: " "))
        case "clear-name":
            guard args.count == 2 else {
                throw FlashError.usage("Usage: swiftflash media clear-name <device-uuid>")
            }
            return .mediaClearName(id: args[1])
        default:
            throw FlashError.usage("Unknown media subcommand: \(subcommand)")
        }
    }

    private static func parseLegacyDevicesArguments(_ args: [String]) throws -> FlashCommand {
        guard let subcommand = args.first else {
            return .mediaList
        }
        switch subcommand {
        case "connected":
            return .mediaList
        case "known":
            return .mediaKnown
        case "name":
            guard args.count >= 3 else {
                throw FlashError.usage("Usage: swiftflash devices name <device-uuid> <name>")
            }
            return .mediaName(id: args[1], name: args[2...].joined(separator: " "))
        case "clear-name":
            guard args.count == 2 else {
                throw FlashError.usage("Usage: swiftflash devices clear-name <device-uuid>")
            }
            return .mediaClearName(id: args[1])
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

    private static func tokenize(line: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var activeQuote: Character?
        var escapeNext = false

        for character in line {
            if escapeNext {
                current.append(character)
                escapeNext = false
                continue
            }

            if character == "\\" {
                escapeNext = true
                continue
            }

            if let quote = activeQuote {
                if character == quote {
                    activeQuote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "\"" || character == "'" {
                activeQuote = character
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }

            current.append(character)
        }

        if escapeNext {
            current.append("\\")
        }

        guard activeQuote == nil else {
            throw FlashError.usage("Unterminated quoted string")
        }

        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}

public struct HelpRenderer {
    public static let text = """
    SwiftFlashCLI

    Run without arguments to start the interactive shell.
    Type `exit`, `quit`, or `quite` to leave it.

    Flash an image to an external physical drive:
      sudo swiftflash [image_file] [/dev/diskX]
      sudo swiftflash flash [image_file] [/dev/diskX] [--yes]

    Verify a flashed image against a raw device:
      sudo swiftflash verify [image_file] [/dev/diskX]

    List remembered images:
      swiftflash images

    List currently connected eligible flash media:
      swiftflash media list

    Show remembered media inventory:
      swiftflash media known

    Show one remembered medium by name or device UUID:
      swiftflash media info <name-or-device-uuid>

    Create device UUIDs for writable connected media if needed:
      swiftflash media identify
      swiftflash identify

    List or manage media types:
      swiftflash media types
      swiftflash media type-add <type-name>
      swiftflash media set-type <device-uuid> <type-name>
      swiftflash media clear-type <device-uuid>

    Set or clear a custom name for a remembered medium:
      swiftflash media name <device-uuid> <name>
      swiftflash media clear-name <device-uuid>

    Show flash history:
      swiftflash history
      swiftflash history clear

    Typical flow:
      1. Run `swiftflash media list` to see connected target media.
      2. Run `sudo swiftflash /path/to/image.iso /dev/diskX` to flash directly.
      3. Or run `sudo swiftflash` and select the image and device interactively.
      4. At the end of the write phase, choose whether to verify before metadata is written.

    Notes:
      - Flashing requires root privileges.
      - Verification also requires root privileges.
      - Only external physical whole disks are eligible targets.
      - `swiftflash media list` shows connected media, not just remembered ones.
      - `swiftflash media identify` creates a `device-uuid` on writable new media when possible.
      - Media types are stored in config and come with preconfigured defaults like `USB Stick`, `SD Card`, and `Micro SD Card`.
      - `swiftflash media list` shows whether the `device-uuid` was reused from `.uuid`, reused from the trailer, or is still unassigned.
      - Legacy `swiftflash devices ...` commands are still accepted as aliases.
    """
}
