# Release Plan

This file tracks which requirements are already included in a release and which items are still open.

## Release 0.1.0

status: implemented

Included requirements:
- pure Swift CLI implementation
- no dependency on external tools like `diskutil` or `dd`
- flashing via `sudo swiftflash [image_file] [/dev/diskX]`
- optional interactive image and device selection
- remembered image list in `~/.swiftflash/config.json`
- scan only external physical whole-disk devices
- maintain remembered device inventory
- maintain flash history
- support `swiftflash devices`, `images`, `history`, `verify`
- optional post-flash verification
- `.uuid` file read/write on writable mounted filesystems
- trailer metadata fallback at end of device if enough free slack exists
- generated `device-uuid` can be created early for writable new devices
- output shows whether identification came from `.uuid`, trailer, or was newly created
- output shows which `device-uuid` and `flash UUID` were written
- progress bar and transfer speed during flash/verify
- image size is checked against target device size

Known gaps:
- real hardware validation is still limited
- no explicit release/version command yet
- no full config cleanup/reset command yet
- no editing of custom user-defined device fields from the CLI yet

## Later Releases 
Planned requirements:
- `swiftflash version`


Potenial requirements:
- `swiftflash version`
- `swiftflash reset` or targeted cleanup commands for images, devices, and config
- CLI commands to edit user-defined device fields
- improved device listing and formatting for multiple similar readers/cards
- clearer distinction between device metadata and flashed image metadata in history output
- stronger validation on unusual partition layouts and edge cases
- stable shared core API prepared for direct GUI reuse
- import/export or migration support for shared GUI/CLI config handling
- extended verification modes
- improved real-device compatibility testing across USB sticks, SD cards, and card readers
- packaging/distribution strategy for end users
