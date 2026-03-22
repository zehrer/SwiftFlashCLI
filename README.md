# SwiftFlashCLI

`SwiftFlashCLI` is a macOS command-line tool for flashing image files such as `.iso` and `.img` to external physical drives.

It is implemented 100% in Swift and uses only system frameworks and APIs:
- `Foundation`
- `DiskArbitration`
- `IOKit`
- `Darwin` / POSIX I/O
- `CryptoKit`

No dependency on `diskutil`, `dd`, or other external tools is used for scanning, mounting, unmounting, or writing.

## Status

The current version provides:
- interactive or argument-based flashing
- remembered image history
- remembered device UUID inventory
- flash history persistence
- best-effort `.uuid` metadata read/write on flashed media
- optional post-flash verification
- raw end-of-device trailer metadata when there is enough safe unused space
- a reusable `SwiftFlashCore` library target for later GUI integration

The code compiles and the automated tests pass. Real hardware flashing should still be treated as the next validation step.

Release overview and planned follow-up work:
- [RELEASE.md](RELEASE.md)

## Requirements

- macOS 13 or later
- Swift 6.2 toolchain via Xcode
- `sudo` for actual flashing operations

## Build

```bash
xcrun swift build
```

Run tests:

```bash
xcrun swift test
```

Run the CLI:

```bash
./.build/debug/swiftflash help
```

## Usage

Main command:

```bash
sudo swiftflash [image_file] [/dev/diskX]
```

Explicit subcommand form:

```bash
sudo swiftflash flash [image_file] [/dev/diskX] [--yes]
```

Additional commands:

```bash
swiftflash images
swiftflash devices
swiftflash devices known
swiftflash devices name <device-uuid> <name>
swiftflash devices clear-name <device-uuid>
swiftflash history
swiftflash history clear
sudo swiftflash verify /path/to/image.iso /dev/diskX
```

### Interactive behavior

- If no image is provided, the tool shows remembered images and allows entering a new path.
- If no device is provided, the tool scans for external physical whole disks and offers an interactive selection.
- If exactly one eligible device is found, that device is proposed directly.
- If a new writable device has no UUID metadata yet, the tool can create a `deviceUUID` marker immediately so later scans can reuse it.
- Unless `--yes` is used, the flash flow asks for final destructive confirmation.

## Persistence

The CLI stores its shared config at:

```text
~/.swiftflash/config.json
```

When run under `sudo`, the tool resolves this path against the invoking user so config is still written to the user account rather than root.

The persisted schema contains:
- `rememberedImages`
- `knownPhysicalDevices`
- `knownFlashMedia`
- `flashHistory`

`knownPhysicalDevices` is intentionally minimal and keeps only tool-managed device UUIDs plus user-meaningful metadata. It does not persist reader-derived vendor/model labels.

This layout is intended to stay compatible with future integration into the SwiftFlash GUI project.

## Flash Flow

The implemented flashing flow is:

1. Validate the image path and file size.
2. Scan only eligible external physical whole-disk devices.
3. Read an existing `/.uuid` file from mounted partitions if available.
4. Unmount the selected disk through Disk Arbitration.
5. Write the image directly to the raw device node using POSIX I/O in Swift.
6. Show a single-line progress bar with transfer speed.
7. Optionally verify the raw device contents against the source image before metadata is written.
8. Flush data with `fsync` and `F_FULLFSYNC` where available.
9. Attempt to remount writable partitions.
10. Write a new `/.uuid` JSON file if a writable mounted partition is available.
11. If no writable filesystem is available and enough slack remains after the image, write trailer metadata in the last 4 KiB of the device.
12. Persist image usage, device inventory, and flash history.

## Package Layout

```text
Sources/
  SwiftFlashCore/
  swiftflash/
Tests/
  SwiftFlashCoreTests/
```

- `SwiftFlashCore` contains models, persistence, device scanning, Disk Arbitration helpers, UUID metadata handling, and the flash service.
- `swiftflash` contains the CLI entrypoint and command execution wiring.

## Current Limitations

- The project is currently macOS-only.
- Flashing requires the process to already run as root, typically via `sudo`.
- Real-device flashing has not yet been fully validated on multiple hardware types.

## License

MIT. See [LICENSE](LICENSE).
