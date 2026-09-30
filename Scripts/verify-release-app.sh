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
model_path="$app_path/Contents/Resources/Models/RealESRGAN_x2plus_522_fp16.mlpackage"

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
if [[ "$notice_count" -ne 7 ]]; then
    echo "Expected 7 third-party notices, found $notice_count." >&2
    exit 1
fi

if [[ ! -d "$model_path" ]]; then
    echo "Bundled restoration model is missing: $model_path" >&2
    exit 1
fi

verify_checksum() {
    local expected="$1"
    local file="$2"
    local actual
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        echo "Bundled restoration model checksum mismatch: $file" >&2
        exit 1
    fi
}

verify_checksum "6f4af8152eba8589bee31c7fe341a5b35534f06330056606a6df099589395790" "$model_path/Manifest.json"
verify_checksum "b79575977211ba89fb7856076e652fdd34f822b5228858e15b8d61169720e1ac" "$model_path/Data/com.apple.CoreML/model.mlmodel"
verify_checksum "a8904f0bb627d5dbce2468a96c648764a63ece561cfcf118da6321831bb3a926" "$model_path/Data/com.apple.CoreML/weights/weight.bin"
verify_checksum "4a699ec4863d96a91fc265948a0c90033f7e8735d515524dcf3444736406e0c2" "$notices_path/Real-ESRGAN-LICENSE.txt"

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
"$ffmpeg_path" -hide_banner -encoders | grep -q ' png '
"$ffmpeg_path" -hide_banner -decoders | grep -q ' png '
"$ffmpeg_path" -hide_banner -formats | grep -q ' image2 '
"$ffmpeg_path" -hide_banner -demuxers | grep -q ' concat '

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")"
echo "Verified SwiftyTranscoder ${version} (${build_number}): arm64 app, signed bundled helpers, restoration model, notices, and required media capabilities."
