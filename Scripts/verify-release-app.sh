#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: Scripts/verify-release-app.sh /path/to/SwiftyTranscoder.app" >&2
    exit 2
fi

app_path="$1"
executable_path="$app_path/Contents/MacOS/SwiftyTranscoder"
helpers_path="$app_path/Contents/Helpers"
notices_path="$app_path/Contents/Resources/ThirdPartyNotices"
ffmpeg_path="$helpers_path/ffmpeg"
ffprobe_path="$helpers_path/ffprobe"

if [[ ! -d "$app_path" || ! -x "$executable_path" ]]; then
    echo "SwiftyTranscoder application is incomplete: $app_path" >&2
    exit 1
fi

for helper in "$ffmpeg_path" "$ffprobe_path"; do
    if [[ ! -x "$helper" ]]; then
        echo "Bundled helper is missing or not executable: $helper" >&2
        exit 1
    fi
done

if [[ ! -d "$notices_path" ]]; then
    echo "Third-party notices are missing: $notices_path" >&2
    exit 1
fi

notice_count="$(find "$notices_path" -type f | wc -l | tr -d ' ')"
if [[ "$notice_count" -ne 6 ]]; then
    echo "Expected 6 third-party notices, found $notice_count." >&2
    exit 1
fi

architectures="$(lipo -archs "$executable_path")"
if [[ "$architectures" != "arm64" ]]; then
    echo "Expected an arm64-only application, found: $architectures" >&2
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app_path"
codesign --verify --strict --verbose=2 "$ffmpeg_path"
codesign --verify --strict --verbose=2 "$ffprobe_path"

for helper in "$ffmpeg_path" "$ffprobe_path"; do
    if otool -L "$helper" | awk 'NR > 1 { print $1 }' | grep -Eq '^(/opt/homebrew|/usr/local)/'; then
        echo "A package-manager library path remains in $helper:" >&2
        otool -L "$helper" >&2
        exit 1
    fi
done

"$ffmpeg_path" -hide_banner -version | grep -q '^ffmpeg version 9\.0\.2'
"$ffprobe_path" -hide_banner -version | grep -q '^ffprobe version 9\.0\.2'
"$ffmpeg_path" -hide_banner -filters | grep -q ' subtitles '
"$ffmpeg_path" -hide_banner -encoders | grep -q 'hevc_videotoolbox'

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")"
echo "Verified SwiftyTranscoder ${version} (${build_number}): arm64 app, signed bundled helpers, notices, and required media capabilities."
