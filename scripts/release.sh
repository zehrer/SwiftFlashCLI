#!/bin/zsh
# Builds a release archive and the Homebrew formula for it.
# Usage: scripts/release.sh <version>   (e.g. 0.2.0)
#
# Does not tag, push or upload anything; it prints those steps at the end.
set -euo pipefail

version="${1:-}"
if [[ -z "$version" ]]; then
  echo "Usage: scripts/release.sh <version>" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

code_version=$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/SwiftFlashCore/Version.swift)
if [[ "$code_version" != "$version" ]]; then
  echo "Version mismatch: Version.swift has $code_version, releasing $version" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean; commit first." >&2
  exit 1
fi

echo "Running tests…"
xcrun swift test

echo "Building release binary (arm64)…"
scratch=.build/release-artifacts
xcrun swift build -c release --arch arm64 --scratch-path "$scratch"
bin_path=$(xcrun swift build -c release --arch arm64 --scratch-path "$scratch" --show-bin-path)

built_version=$("$bin_path/swiftflash" --version)
if [[ "$built_version" != "swiftflash $version" ]]; then
  echo "Built binary reports '$built_version'" >&2
  exit 1
fi

dist=dist
archive="swiftflash-$version-macos-arm64.tar.gz"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
mkdir -p "$dist"
cp "$bin_path/swiftflash" LICENSE "$staging/"
tar -czf "$dist/$archive" -C "$staging" swiftflash LICENSE
sha256=$(shasum -a 256 "$dist/$archive" | cut -d' ' -f1)

sed -e "s/@VERSION@/$version/g" -e "s/@SHA256@/$sha256/g" \
  packaging/homebrew/swiftflash.rb.template > "$dist/swiftflash.rb"

cat <<NEXT

Created:
  $dist/$archive
  $dist/swiftflash.rb   (sha256 $sha256)

Next steps:
  git tag v$version && git push origin v$version
  gh release create v$version "$dist/$archive" --title "v$version" --generate-notes
  cp $dist/swiftflash.rb <homebrew-tap checkout>/Formula/swiftflash.rb   # then commit and push the tap
NEXT
