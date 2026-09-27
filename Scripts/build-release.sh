#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: Scripts/build-release.sh [--force]"
    echo ""
    echo "Builds, verifies, and packages a local ad-hoc-signed release DMG."
    echo "Use --force to replace an existing DMG for the same version."
}

force=0
case "${1:-}" in
    "") ;;
    --force) force=1 ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

if [[ $# -gt 1 ]]; then
    usage >&2
    exit 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
work_dir="$(mktemp -d /tmp/SwiftyTranscoder-release.XXXXXX)"
derived_data="$work_dir/DerivedData"
staging_dir="$work_dir/DMG"
temporary_dmg="$work_dir/SwiftyTranscoder.dmg"
mounted=0
mount_dir=""

cleanup() {
    if [[ $mounted -eq 1 && -n "$mount_dir" ]]; then
        hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
    fi
    case "$work_dir" in
        /tmp/SwiftyTranscoder-release.*) rm -rf "$work_dir" ;;
    esac
}
trap cleanup EXIT

cd "$project_root"

echo "Running regression tests…"
swift test

echo "Preparing the self-contained media toolchain…"
"$script_dir/build-toolchain.sh"
"$script_dir/stage-toolchain-bundle.sh"

echo "Building SwiftyTranscoder Release configuration…"
xcodebuild \
    -quiet \
    -project SwiftyTranscoder.xcodeproj \
    -scheme SwiftyTranscoder \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    build

app_path="$derived_data/Build/Products/Release/SwiftyTranscoder.app"
executable_path="$app_path/Contents/MacOS/SwiftyTranscoder"

if [[ ! -d "$app_path" || ! -x "$executable_path" ]]; then
    echo "Release app was not found at $app_path" >&2
    exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")"
architectures="$(lipo -archs "$executable_path" | tr ' ' '_')"
dmg_name="SwiftyTranscoder_${version}_${architectures}.dmg"
dist_dir="$project_root/dist"
dmg_path="$dist_dir/$dmg_name"
checksum_path="$dist_dir/SHA256SUMS.txt"

if [[ -e "$dmg_path" && $force -ne 1 ]]; then
    echo "Release already exists: $dmg_path" >&2
    echo "Run Scripts/build-release.sh --force to replace it." >&2
    exit 1
fi

echo "Verifying SwiftyTranscoder ${version} (${build_number})…"
"$script_dir/verify-release-app.sh" "$app_path"

mkdir -p "$staging_dir" "$dist_dir"
ditto "$app_path" "$staging_dir/SwiftyTranscoder.app"
ln -s /Applications "$staging_dir/Applications"

echo "Creating ${dmg_name}…"
diskutil image create from \
    --volumeName "SwiftyTranscoder" \
    --format UDZO \
    "$staging_dir" \
    "$temporary_dmg"

hdiutil verify "$temporary_dmg"

mount_dir="$work_dir/MountedDMG"
mkdir -p "$mount_dir"
echo "Mounting the DMG for an independent packaged-app check…"
hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$temporary_dmg" >/dev/null
mounted=1
if [[ ! -L "$mount_dir/Applications" ]]; then
    echo "The mounted DMG is missing its Applications shortcut." >&2
    exit 1
fi
"$script_dir/verify-release-app.sh" "$mount_dir/SwiftyTranscoder.app"
hdiutil detach "$mount_dir" >/dev/null
mounted=0

if [[ -e "$dmg_path" ]]; then
    rm "$dmg_path"
fi
cp "$temporary_dmg" "$dmg_path"

checksum_line="$(shasum -a 256 "$dmg_path" | awk -v name="$dmg_name" '{ print $1 "  " name }')"
printf '%s\n' "$checksum_line" > "$checksum_path.tmp"
mv -f "$checksum_path.tmp" "$checksum_path"

echo ""
echo "Release complete:"
echo "  $dmg_path"
echo "  $checksum_path"
echo "  $checksum_line"
