# Publishing images for SwiftFlash

This guide is for teams that publish OS images on a build server and want them to be easy
and safe to flash with [SwiftFlash](../README.md). It describes what SwiftFlash expects from
the server, what is optional, and why.

## How SwiftFlash uses the server

A user registers the image directory once:

```bash
swiftflash source add redox http://homenodellm:8080/sdcard/
```

and then flashes the newest build of an image family without copying URLs:

```bash
sudo swiftflash redox:t18-direct          # newest build of redox-rpi-t18-direct
sudo swiftflash redox:                    # pick family and build from a list
swiftflash source browse redox            # list all families with their newest build
```

For that, SwiftFlash:

1. Reads `index.json` from the directory, or, if there is none, the HTML directory listing.
2. Groups the image files into **families** by file name and finds the **newest build** of each
   (by the date in `index.json`, else by the server's `Last-Modified` header, else by file name).
3. Downloads the chosen image and checks it against `<image>.sha256` if present.
4. Unpacks `.xz`, writes the image, and reads the image's identity from `/.uuid` on the card.
5. Moves the download to the user's Trash and reuses it next time if the server still serves
   the same file (`ETag`, or `Last-Modified` plus size).

## Requirements

### 1. HTTP directory per image collection

- Serve the images over HTTP or HTTPS, one directory per collection (e.g. `/sdcard/`).
- Either enable a **directory listing** or publish an **`index.json`** (see below).
  `python3 -m http.server` works out of the box.
- No authentication is supported yet.

### 2. File names: `<family>-<version>.<ext>`

SwiftFlash derives family and version from the file name when there is no `index.json`:

| Part | Rule | Example |
| --- | --- | --- |
| family | stable name of the image variant, never contains the version | `redox-rpi-t18-direct` |
| version | starts with `v<major>.<minor>` (e.g. `git describe`) **or** with a date `YYYYMMDD` | `v0.4.0-dev-36-g1107e5f7+x95e1`, `20261107b` |
| extension | `.img`, `.iso`, optionally compressed as `.xz` | `.img.xz` |

Good:

```text
redox-rpi-t18-direct-v0.4.0-dev-36-g1107e5f7+x95e1.img.xz
redox-rpi-bootcode-monitor-3bp-20261107b.img.xz
```

Not recognised as a version (the whole name becomes the family, so every build is its own family):

```text
redox-rpi-zero2w-fastnet-db5ea27.img.xz      # only a commit hash
redox-rpi-grow-root-v3.img.xz                # no dot after the major version
```

Also keep family names distinguishable: users type short forms such as `redox:t18-direct`.
A short form that matches several families (e.g. `3bp`) is rejected with a list of candidates.

### 3. Never overwrite a published build

- A new build gets a **new file name**. Do not replace a file under the same name.
- If you do publish a fixed name (e.g. a `-latest` alias), the server must report a new
  `Last-Modified` (and ideally `ETag`) and the new size. Otherwise SwiftFlash may reuse an old
  download from the user's Trash.

### 4. HTTP headers

The server must answer `HEAD` requests and send:

- `Content-Length`
- `Last-Modified` (used for "newest build" without `index.json`, and for reuse checks)
- `ETag` is optional but preferred for reuse checks

`python3 -m http.server`, nginx and Caddy do this by default.

### 5. Compression

- Use `.xz` (e.g. `xz -9`).
- `.gz` is **not supported yet**.

## Recommended

### Checksum file: `<image>.sha256`

Publish a checksum for every image file, next to it, in `sha256sum` format, for the file **as
published** (the compressed `.xz`):

```bash
sha256sum redox-rpi-t18-direct-v0.4.0-dev-36-g1107e5f7+x95e1.img.xz \
  > redox-rpi-t18-direct-v0.4.0-dev-36-g1107e5f7+x95e1.img.xz.sha256
```

SwiftFlash stops if a download does not match, and re-downloads if a reused copy does not match.

### Image identity: `/.uuid` with an `image` block

Put a `.uuid` file into the root of the image's FAT boot partition so the flashed card can tell
which image and version it carries:

```json
{
  "schemaVersion": 1,
  "image": {
    "id": "redox-rpi-t18-direct",
    "name": "Redox OS",
    "version": "v0.4.0-dev-36-g1107e5f7+x95e1",
    "build": "2026-11-02T20:50:32Z",
    "commit": "1107e5f7"
  }
}
```

Do **not** include `deviceUUID` or `flashUUID`. SwiftFlash keeps the `image` block and adds its
own fields after flashing; `swiftflash media list` then shows e.g.
`image:Redox OS v0.4.0-dev-36-g1107e5f7+x95e1`. Full format: [uuid-file.md](uuid-file.md).

Using the same `id` as the file family and the same `version` as in the file name keeps
everything consistent.

## Optional: `index.json`

An `index.json` in the image directory replaces name guessing and `HEAD` requests. SwiftFlash
uses it automatically when present.

```json
{
  "images": [
    {
      "file": "redox-rpi-t18-direct-v0.4.0-dev-36-g1107e5f7+x95e1.img.xz",
      "family": "redox-rpi-t18-direct",
      "version": "v0.4.0-dev-36-g1107e5f7+x95e1",
      "date": "2026-11-02T20:50:32Z"
    },
    {
      "file": "redox-rpi-zero2w-fastnet-db5ea27.img.xz",
      "family": "redox-rpi-zero2w-fastnet",
      "version": "db5ea27",
      "date": "2026-10-29T09:42:00Z"
    }
  ]
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `file` | yes | File name (or path relative to the directory). Must end in `.img`, `.iso`, `.img.xz` or `.iso.xz`. |
| `family` | no | Image family. Defaults to the family derived from the file name. |
| `version` | no | Version shown to the user. Defaults to the version derived from the file name. |
| `date` | no | Build time, ISO 8601 with time zone. Used to find the newest build. |

Unknown fields are ignored, so you can add your own (board, channel, commit, …). Other files
in the directory (`.sha256`, `.manifest.toml`, …) are ignored.

### Generating `index.json` in the build

Example, run in the image directory after each build:

```python
#!/usr/bin/env python3
import datetime, json, pathlib, re

pattern = re.compile(r"^(?P<family>.+?)-(?P<version>v\d+\.\d+.*|\d{8}.*)\.img\.xz$")
images = []
for path in sorted(pathlib.Path(".").glob("*.img.xz")):
    match = pattern.match(path.name)
    entry = {
        "file": path.name,
        "date": datetime.datetime.fromtimestamp(path.stat().st_mtime, datetime.timezone.utc)
                .isoformat(timespec="seconds").replace("+00:00", "Z"),
    }
    if match:
        entry["family"] = match["family"]
        entry["version"] = match["version"]
    images.append(entry)

tmp = pathlib.Path("index.json.tmp")
tmp.write_text(json.dumps({"images": images}, indent=2))
tmp.replace("index.json")  # atomic, so clients never read a half-written file
```

## Cleaning up old builds

Deleting old builds from the server is fine. `redox:<family>` always picks from what is on the
server. A user who selects a deleted build by its full URL (e.g. from the remembered image list)
gets an HTTP 404; a copy in their Trash is then only used if the server is unreachable.

## Checklist

- [ ] Images are in an HTTP directory with a listing or an `index.json`
- [ ] File names follow `<family>-<version>.img.xz` (version starts with `v1.2` or `YYYYMMDD`), or `index.json` provides family and version
- [ ] A published file is never overwritten under the same name
- [ ] Server answers `HEAD` with `Content-Length` and `Last-Modified`
- [ ] Compression is `.xz` (not `.gz`)
- [ ] Every image has a `<image>.sha256` in `sha256sum` format
- [ ] The image contains `/.uuid` with only `schemaVersion` and an `image` block on the FAT boot partition
