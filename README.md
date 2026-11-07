# SwiftFlashCLI

`SwiftFlashCLI` is a macOS command-line tool for flashing image files such as `.iso` and `.img` to external physical drives.
Images can also be `.xz` compressed (e.g. `.img.xz`) and can be loaded from an `http(s)` URL.

It is implemented 100% in Swift and uses only system frameworks and APIs:
- `Foundation`
- `DiskArbitration`
- `IOKit`
- `Darwin` / POSIX I/O
- `CryptoKit`
- `Compression` (xz decoding)

No dependency on `diskutil`, `dd`, `xz`, `curl`, or other external tools is used for scanning, mounting, unmounting, downloading, unpacking, or writing.

## Status

The current version provides:
- interactive or argument-based flashing
- remembered image history
- remembered device UUID inventory
- configurable media types with preconfigured defaults
- flash history persistence
- best-effort `.uuid` metadata read/write on flashed media, including an image-provided `image` block (see [docs/uuid-file.md](docs/uuid-file.md))
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

## Install

With Homebrew (once the tap is published):

```bash
brew install zehrer/tap/swiftflash
swiftflash --version
```

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

Run without arguments to start the interactive shell:

```bash
./.build/debug/swiftflash
```

## Usage

Main command:

```bash
sudo swiftflash [image_file] [/dev/diskX]
```

Interactive shell:

```bash
swiftflash
```

Inside the shell, type commands like `flash`, `media list`, or `history`.
Leave the shell with `exit`, `quit`, or `quite`.

Explicit subcommand form:

```bash
sudo swiftflash flash [image_file] [/dev/diskX] [--yes]
```

Additional commands:

```bash
swiftflash images
swiftflash images remove <name-or-path>
swiftflash images clear
swiftflash media list
swiftflash media known
swiftflash media info <name-or-device-uuid>
swiftflash media identify
swiftflash identify
swiftflash media types
swiftflash media type-add <type-name>
swiftflash media set-type <device-uuid> <type-name>
swiftflash media clear-type <device-uuid>
swiftflash media name <device-uuid> <name>
swiftflash media clear-name <device-uuid>
swiftflash history
swiftflash history clear
swiftflash version
sudo swiftflash verify /path/to/image.iso /dev/diskX
```

### Compressed and remote images

```bash
sudo swiftflash /path/to/sdcard.img.xz /dev/diskX
sudo swiftflash http://192.168.178.120:8080/redox/sdcard-redox.img.xz /dev/diskX
```

- `.xz` images are unpacked into a temporary directory before flashing; the original `.xz` file is kept.
- Remote images are downloaded into a temporary directory.
- After flashing or verifying (also when the operation fails), the downloaded file is moved to the Trash of the user who ran `sudo`, and the unpacked image is deleted.
- The next time the same URL is used, SwiftFlash asks the server (HEAD request) whether the file is unchanged (`ETag`, or `Last-Modified` plus size). If so, it takes the copy from the Trash instead of downloading again. If the server is not reachable, the copy from the Trash is used.
- Emptying the Trash simply means the image is downloaded again next time.
- If a `<image>.sha256` file (`sha256sum` format) is published next to the image, SwiftFlash checks the downloaded file against it and stops on a mismatch. A copy from the Trash is checked too; if it does not match, the image is downloaded again. When the server is offline, the copy is checked against the SHA-256 recorded at download time.
- The same works for local files: `image.img.xz` is checked if `image.img.xz.sha256` lies next to it.
- The remembered image list stores the original location (URL or `.xz` path), so the same source can be selected again later.
- The temporary directory needs enough free space for the unpacked image.

### Image sources

A build server directory can be registered once and then used by short names:

```bash
swiftflash source add redox http://homenodellm:8080/sdcard/
swiftflash source browse redox              # families with their newest build
swiftflash source browse redox t18-direct   # all builds of one family
sudo swiftflash redox:t18-direct            # flash the newest build of that family
sudo swiftflash redox:                      # choose family and build interactively
```

- The family can be given in full (`redox-rpi-t18-direct`), as a suffix (`t18-direct`) or as a unique part (`t18`).
- The interactive image selection also offers `redox) Browse …`.
- SwiftFlash reads `index.json` if the server has one, otherwise the directory listing plus `Last-Modified`.
- What a build server should provide is described in [docs/build-server.md](docs/build-server.md); hand it to the team running the server.

### Interactive behavior

- If no image is provided, the tool shows remembered images and allows entering a new path.
- If no device is provided, the tool scans for external physical whole disks and offers an interactive selection.
- If exactly one eligible device is found, that device is proposed directly.
- If no command is provided, the tool starts an interactive REPL-style shell.
- `swiftflash media identify` can create a `device-uuid` marker on a writable new medium so later scans can reuse it.
- Unless `--yes` is used, the flash flow asks for final destructive confirmation.

## Persistence

The CLI stores its shared config at:

```text
~/.swiftflash/config.json
```

When run under `sudo`, the tool resolves this path against the invoking user so config is still written to the user account rather than root.

The persisted schema contains:
- `mediaTypes`
- `rememberedImages`
- `knownPhysicalDevices`
- `knownFlashMedia`
- `flashHistory`

`knownPhysicalDevices` is intentionally minimal and keeps only tool-managed device UUIDs plus user-meaningful metadata. It does not persist reader-derived vendor/model labels.

`mediaTypes` are regular config data, not a hard-coded enum. A fresh config starts with:
- `USB Stick`
- `SD Card`
- `Micro SD Card`

This layout is intended to stay compatible with future integration into the SwiftFlash GUI project.

## Flash Flow

The implemented flashing flow is:

1. Download remote images and unpack `.xz` images into a temporary directory, then validate the image file and size.
2. Scan only eligible external physical whole-disk devices.
3. Read an existing `/.uuid` file from mounted partitions if available.
4. Unmount the selected disk through Disk Arbitration.
5. Write the image directly to the raw device node using POSIX I/O in Swift.
6. Show a single-line progress bar with transfer speed.
7. Optionally verify the raw device contents against the source image before metadata is written.
8. Flush data with `fsync` and `F_FULLFSYNC` where available.
9. Attempt to remount writable partitions.
10. Write a new `/.uuid` JSON file if a writable mounted partition is available, keeping the `image` block an image may ship in its own `/.uuid` ([format](docs/uuid-file.md)).
11. If no writable filesystem is available and enough slack remains after the image, write trailer metadata in the last 4 KiB of the device.
12. Persist image usage, device inventory, and flash history.
13. Unmount all partitions of the medium so it can be removed safely (also after `verify`).
14. Move a fresh download to the Trash for reuse and delete the other temporary files.

## Releasing

```bash
scripts/release.sh 0.2.0
```

The script checks that `Sources/SwiftFlashCore/Version.swift` matches, requires a clean working tree, runs the tests,
builds an arm64 release binary, and writes `dist/swiftflash-<version>-macos-arm64.tar.gz` plus a ready Homebrew
formula `dist/swiftflash.rb` (from `packaging/homebrew/swiftflash.rb.template`). It prints the tag, GitHub release and
tap steps but does not run them.

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
