# SwiftFlashCLI

`swiftflash` is a macOS command-line tool for flashing `.img` and `.iso` images to SD cards and USB sticks.
Images can be local files, `.xz` compressed, or loaded from an `http(s)` URL or a registered build server.

It is implemented 100% in Swift and uses only system frameworks:
`Foundation`, `DiskArbitration`, `IOKit`, `Darwin` / POSIX I/O, `CryptoKit` and `Compression`.
No external tools such as `diskutil`, `dd`, `xz` or `curl` are used for scanning, mounting, downloading,
unpacking or writing.

## Install

```bash
brew install zehrer/tap/swiftflash
swiftflash --version
```

The Homebrew build runs on Apple Silicon Macs with macOS 13 or later. See [Build](#build) to build it yourself.

## Quick start

```bash
swiftflash media list                                      # connected SD cards / USB sticks
sudo swiftflash ~/Downloads/image.img.xz /dev/disk6        # flash a local (compressed) image
sudo swiftflash https://example.com/images/os.img.xz       # flash a remote image
sudo swiftflash                                            # choose image and device interactively
```

Flashing and verifying need `sudo`. Only external physical whole disks are offered as targets, and unless
`--yes` is given, SwiftFlash shows what is currently on the medium and asks before erasing it.

## Features

- Flash `.img` / `.iso`, also `.xz` compressed, from a local path or an `http(s)` URL
- Image sources: register a build server directory once, then flash the newest build with `redox:<family>`
- Downloads are checked against a published `<image>.sha256` and kept in the Trash for reuse
- Optional verification of the written medium against the image
- Device selection and erase confirmation show the known name, media type and the image currently on the medium
- Identification of media and flashed images via a small `/.uuid` file ([format](docs/uuid-file.md)), with a raw
  trailer copy at the end of the device when there is room
- Remembered images, media inventory with names and media types, and flash history
- The medium is unmounted after flashing, so it can be removed right away
- Interactive shell when started without arguments
- Reusable `SwiftFlashCore` library target for a future GUI

## Usage

```bash
sudo swiftflash [image] [/dev/diskX]
sudo swiftflash flash [image] [/dev/diskX] [--yes]
sudo swiftflash verify [image] [/dev/diskX]
```

`image` can be a local path, an `http(s)` URL, or `<source>:<family>` (see [Image sources](#image-sources)).
Without arguments, `swiftflash` starts an interactive shell; type commands like `flash`, `media list` or
`history`, and leave it with `exit` or `quit`.

All commands (`swiftflash help` shows the same list):

```bash
swiftflash images                                 # remembered images
swiftflash images remove <name-or-path>
swiftflash images clear

swiftflash source add <name> <url>                # image sources (build server directories)
swiftflash source list
swiftflash source browse <name> [family]
swiftflash source remove <name>

swiftflash media list                             # connected eligible media
swiftflash media known                            # remembered media
swiftflash media info <name-or-device-uuid>
swiftflash media identify                         # create a device-uuid on new writable media
swiftflash media types
swiftflash media type-add <type-name>
swiftflash media set-type <device-uuid> <type-name>
swiftflash media clear-type <device-uuid>
swiftflash media name <device-uuid> <name>
swiftflash media clear-name <device-uuid>

swiftflash history
swiftflash history clear
swiftflash version
```

Legacy `swiftflash devices …` commands are still accepted as aliases.

### Compressed and remote images

```bash
sudo swiftflash /path/to/sdcard.img.xz /dev/diskX
sudo swiftflash https://example.com/images/sdcard.img.xz /dev/diskX
```

- `.xz` images are unpacked into a temporary directory; the original `.xz` file is kept. The temporary directory
  needs enough free space for the unpacked image.
- Remote images are downloaded into a temporary directory. After flashing or verifying (also when it fails),
  the downloaded file is moved to the Trash of the user who ran `sudo`, and the unpacked image is deleted.
- The next time the same URL is used, SwiftFlash asks the server whether the file is unchanged (`ETag`, or
  `Last-Modified` plus size) and takes the copy from the Trash instead of downloading again. If the server is not
  reachable, the copy from the Trash is used. An emptied Trash just means the image is downloaded again.
- If a `<image>.sha256` file (`sha256sum` format) lies next to the image, the download is checked against it and
  SwiftFlash stops on a mismatch. A copy from the Trash is checked too and downloaded again if it does not match;
  offline, it is checked against the SHA-256 recorded at download time. Local files are checked the same way.
- The remembered image list stores the original location (URL or `.xz` path), not the temporary file.

### Image sources

Register a build server directory once and use short names:

```bash
swiftflash source add redox http://homenodellm:8080/sdcard/
swiftflash source browse redox              # families with their newest build
swiftflash source browse redox t18-direct   # all builds of one family
sudo swiftflash redox:t18-direct            # flash the newest build of that family
sudo swiftflash redox:                      # choose family and build interactively
```

- The family can be given in full (`redox-rpi-t18-direct`), as a suffix (`t18-direct`) or as a unique part
  (`t18`). An ambiguous short form is rejected with the list of matching families.
- The interactive image selection also offers `redox) Browse …`.
- SwiftFlash reads `index.json` if the server has one, otherwise the directory listing plus `Last-Modified`.
- What a build server should provide is described in [docs/build-server.md](docs/build-server.md).

### Interactive behavior

- Without an image, SwiftFlash lists remembered images and configured sources, and accepts a new path or URL.
- Without a device, it scans for external physical whole disks; a single eligible device is proposed directly.
- For each device it shows whether the medium is known (name, media type, `device-uuid`) and what is on it
  (image version, file and flash date), or the volume names of an unknown medium.
- Unless `--yes` is used, the flash flow asks for a final confirmation and says what will be replaced.
- After writing, it asks whether to verify the medium before metadata is written.

## Persistence

Configuration, inventory and history are stored in:

```text
~/.swiftflash/config.json
```

Under `sudo`, the path is resolved against the invoking user, and the file is handed back to that user after
saving, so later commands without `sudo` can still update it.

The file contains:
- `mediaTypes` — starts with `USB Stick`, `SD Card`, `Micro SD Card`
- `rememberedImages`
- `knownPhysicalDevices` — tool-managed device UUIDs plus user-meaningful metadata (no reader vendor/model labels)
- `knownFlashMedia`
- `flashHistory`
- `trashedDownloads` — downloads kept in the Trash for reuse
- `imageSources`

The layout is intended to stay compatible with a future SwiftFlash GUI.

## Flash flow

1. Resolve `<source>:<family>`, download remote images, check them against `.sha256`, and unpack `.xz` into a
   temporary directory; validate the image file and size.
2. Scan only eligible external physical whole-disk devices and show what is on them.
3. Read an existing `/.uuid` from mounted partitions (or the trailer) to reuse the `device-uuid`.
4. Unmount the whole disk through Disk Arbitration.
5. Write the image to the raw device node with POSIX I/O, showing progress and speed.
6. Optionally verify the raw device contents against the image.
7. Flush data with `fsync` and `F_FULLFSYNC`.
8. Remount the partitions.
9. Write `/.uuid` on a writable partition, keeping an `image` block the image may ship in its own `/.uuid`.
10. If at least 1 MiB is free after the image, also write the metadata into the last 4 KiB of the device.
11. Persist image usage, device inventory and flash history.
12. Unmount the medium so it can be removed (also after `verify`).
13. Move a fresh download to the Trash and delete the other temporary files.

## Build

Requires Xcode with Swift 6.2 or later.

```bash
xcrun swift build
xcrun swift test
./.build/debug/swiftflash help
```

## Releasing

1. Bump `Sources/SwiftFlashCore/Version.swift`, update [RELEASE.md](RELEASE.md), commit and push.
2. Build the archive and the formula:
   ```bash
   scripts/release.sh 0.2.0
   ```
   The script checks the version and a clean working tree, runs the tests, builds an arm64 release binary, and
   writes `dist/swiftflash-<version>-macos-arm64.tar.gz` plus `dist/swiftflash.rb`
   (from `packaging/homebrew/swiftflash.rb.template`).
3. Tag and publish (the script prints these commands):
   ```bash
   git tag v0.2.0 && git push origin v0.2.0
   gh release create v0.2.0 dist/swiftflash-0.2.0-macos-arm64.tar.gz --title v0.2.0
   ```
4. Copy `dist/swiftflash.rb` to `Formula/swiftflash.rb` in [zehrer/homebrew-tap](https://github.com/zehrer/homebrew-tap)
   and push it; `brew upgrade` then offers the new version.

## Package layout

```text
Sources/
  SwiftFlashCore/     models, persistence, device scanning, Disk Arbitration, image download/unpack/checksums,
                      image sources, UUID metadata, flash service
  swiftflash/         CLI entry point, command execution, progress output
Tests/
  SwiftFlashCoreTests/
docs/                 file formats and guides
scripts/              release script
packaging/homebrew/   formula template
```

## Documentation

- [docs/uuid-file.md](docs/uuid-file.md) — the `/.uuid` metadata file and how images can identify themselves
- [docs/build-server.md](docs/build-server.md) — what a build server should provide for SwiftFlash
- [RELEASE.md](RELEASE.md) — release contents and planned work

## Current limitations

- macOS only; the Homebrew build is arm64 only.
- Flashing and verifying require root, typically via `sudo`.
- `.gz` images are not supported yet.
- Tested mainly with SD cards in USB card readers; more hardware coverage is welcome.

## License

MIT. See [LICENSE](LICENSE).
