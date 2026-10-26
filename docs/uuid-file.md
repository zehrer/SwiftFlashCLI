# The `/.uuid` metadata file

SwiftFlash identifies flashed media with a small JSON file named `.uuid` in the root
directory of a partition on the medium. The same file can be shipped inside an image to
tell SwiftFlash (and anyone else reading the medium) which image and version it is.

This document describes the format and who owns which part of it.

## Location

- File name: `.uuid` (hidden, lower case)
- Directory: root of a partition that macOS can mount, typically a FAT/exFAT boot or EFI partition
- Encoding: UTF-8 JSON

When reading, SwiftFlash checks all mounted partitions of the medium. When writing, it
uses the writable partition that already contains a `.uuid`; if there is none, it uses the
first writable mounted partition.

## Example

A `.uuid` on a medium after SwiftFlash has flashed an image that shipped its own `image` block:

```json
{
  "schemaVersion" : 1,
  "deviceUUID" : "0F9A6091-5504-42A7-81FD-A38E3694A152",
  "deviceName" : "Generic MassStorageClass Media",
  "flashUUID" : "E890F5D6-A172-49C0-B7EB-1C21A6A38CB9",
  "flashedAt" : "2026-10-26T13:40:12Z",
  "imageName" : "sdcard-redox.img",
  "imagePath" : "http://192.168.178.120:8080/redox/sdcard-redox.img.xz",
  "imageSHA256" : "37a7b7edc4980b3cb1aa17d028da145a45488a947b453b497ddf9aa3f5c2f5ce",
  "image" : {
    "id" : "sdcard-redox",
    "name" : "Redox OS",
    "version" : "0.9.1",
    "build" : "2026-10-26T12:21:00Z"
  }
}
```

## Fields

### Owned by SwiftFlash

SwiftFlash writes these fields. Images must not contain them.

| Field | Type | Meaning |
| --- | --- | --- |
| `schemaVersion` | integer | Format version, currently `1`. |
| `deviceUUID` | string | Identifies the physical medium. Created once, then kept across every flash of the same medium. |
| `deviceName` | string | Device name as reported by macOS when the UUID was written. |
| `flashUUID` | string (UUID) | Identifies one flash operation. New on every flash. Missing if the medium was only identified, never flashed. |
| `flashedAt` | string (ISO 8601) | Time the metadata was written. |
| `imageName` | string | File name of the flashed image (after unpacking). |
| `imagePath` | string | Original image location: local path, `.xz` path, or `http(s)` URL. |
| `imageSHA256` | string | SHA-256 of the flashed (uncompressed) image. |

In short: `deviceUUID` answers *which medium is this*, `flashUUID` answers *which flash
put the current content on it*.

### Owned by the image: the `image` block

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | string | Machine-readable image id, e.g. `sdcard-redox`. Similar to `IMAGE_ID` in `os-release`. |
| `name` | string | Human-readable name, e.g. `Redox OS`. Similar to `NAME` in `os-release`. |
| `version` | string | Image version, e.g. `0.9.1`. Similar to `IMAGE_VERSION` / `VERSION_ID` in `os-release`. |
| `build` | string | Build id or timestamp, e.g. ISO 8601 date or CI build number. Similar to `BUILD_ID`. |
| any other key | any JSON | Kept unchanged, e.g. `commit`, `channel`, `board`. |

All fields in the `image` block are optional. SwiftFlash shows `name` (or `id`) plus
`version` as the image label, e.g. `Redox OS 0.9.1`.

## For image builders

To make an image identifiable, put a `.uuid` with **only** `schemaVersion` and an `image`
block into the root of the image's FAT/boot partition:

```json
{
  "schemaVersion": 1,
  "image": {
    "id": "sdcard-redox",
    "name": "Redox OS",
    "version": "0.9.1",
    "build": "2026-10-26T12:21:00Z",
    "commit": "a1b2c3d"
  }
}
```

Rules:

1. **No `deviceUUID` and no `flashUUID` in the image.** These identify one physical medium
   and one flash. If an image shipped them, every medium flashed with it would look like the
   same medium.
2. Put the file on a partition macOS can mount (FAT/exFAT), otherwise SwiftFlash cannot read it.
3. Keep the file small (well below 3 KiB), so it also fits into the trailer (see below).
4. Generate it in the build, e.g. from the same values you write to `/etc/os-release`.

What happens when the image is flashed with SwiftFlash:

1. The raw image is written, including your `.uuid`.
2. SwiftFlash mounts the partitions and reads the `image` block from your `.uuid`.
3. It replaces the file with a full `.uuid` that contains its own fields plus your `image`
   block, unchanged, including unknown keys.
4. `swiftflash media list`, `swiftflash media info` and `swiftflash history` show the image label.

When the image is written with another tool (for example `dd`), the `.uuid` stays exactly
as shipped. SwiftFlash then shows the image label but treats the medium as not yet
identified; `swiftflash media identify` adds a `deviceUUID` and keeps the `image` block.

## Trailer copy

If at least 1 MiB of free space remains after the image, SwiftFlash also writes the same
JSON into the last 4 KiB of the device. This is the only copy when the medium has no
writable filesystem macOS can mount:

- Bytes 0–18: the ASCII marker `SWFLASH-TRAILER-V1\n`
- Then: the JSON payload, padded with zero bytes to 4096 bytes

Reading the trailer needs raw device access, i.e. `sudo`.

## Compatibility

- Readers must ignore unknown top-level fields.
- Older files may use `physicalDeviceID` / `physicalDeviceName` instead of
  `deviceUUID` / `deviceName`; SwiftFlash still reads them.
- An incompatible format change will increase `schemaVersion`.
