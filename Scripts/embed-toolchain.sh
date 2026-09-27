#!/bin/bash

set -euo pipefail

project_root="${SRCROOT:?SRCROOT is required}"
app_contents="${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}/${CONTENTS_FOLDER_PATH:?CONTENTS_FOLDER_PATH is required}"
toolchain_root="$project_root/.build/toolchain"
helpers_source="$toolchain_root/bundle/SwiftyTranscoderToolchain/Contents/Helpers"
licenses_source="$toolchain_root/dependencies/share/licenses"
ffmpeg_licenses_source="$toolchain_root/stage/share/licenses/ffmpeg"
helpers_destination="$app_contents/Helpers"
notices_destination="$app_contents/Resources/ThirdPartyNotices"
model_name="RealESRGAN_x2plus_522_fp16.mlpackage"
model_source="$project_root/.build/restoration-evaluation/converter/weights/$model_name"
model_destination="$app_contents/Resources/Models/$model_name"
model_license_source="$project_root/.build/restoration-evaluation/licenses/Real-ESRGAN-LICENSE.txt"
signing_identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"

for helper in ffmpeg ffprobe; do
    if [[ ! -x "$helpers_source/$helper" ]]; then
        echo "error: Missing verified $helper helper. Run Scripts/build-toolchain.sh and Scripts/stage-toolchain-bundle.sh first." >&2
        exit 1
    fi
done

for notice in \
    freetype/LICENSE.TXT \
    fribidi/COPYING \
    harfbuzz/COPYING \
    libass/COPYING; do
    if [[ ! -f "$licenses_source/$notice" ]]; then
        echo "error: Missing third-party notice: $notice" >&2
        exit 1
    fi
done

for notice in COPYING.LGPLv2.1 LICENSE.md; do
    if [[ ! -f "$ffmpeg_licenses_source/$notice" ]]; then
        echo "error: Missing FFmpeg notice: $notice" >&2
        exit 1
    fi
done

if [[ ! -d "$model_source" || ! -f "$model_license_source" ]]; then
    echo "error: Missing verified restoration model or license. Run Scripts/prepare-restoration-model.sh first." >&2
    exit 1
fi

verify_checksum() {
    local expected="$1"
    local file="$2"
    local actual
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        echo "error: Restoration model checksum mismatch: $file" >&2
        exit 1
    fi
}

verify_checksum "6f4af8152eba8589bee31c7fe341a5b35534f06330056606a6df099589395790" "$model_source/Manifest.json"
verify_checksum "b79575977211ba89fb7856076e652fdd34f822b5228858e15b8d61169720e1ac" "$model_source/Data/com.apple.CoreML/model.mlmodel"
verify_checksum "a8904f0bb627d5dbce2468a96c648764a63ece561cfcf118da6321831bb3a926" "$model_source/Data/com.apple.CoreML/weights/weight.bin"
verify_checksum "4a699ec4863d96a91fc265948a0c90033f7e8735d515524dcf3444736406e0c2" "$model_license_source"

mkdir -p "$helpers_destination" "$notices_destination" "$(dirname "$model_destination")"

for helper in ffmpeg ffprobe; do
    destination="$helpers_destination/$helper"
    cp "$helpers_source/$helper" "$destination"
    chmod 755 "$destination"
    codesign --force --sign "$signing_identity" --options runtime --timestamp=none "$destination"
done

cp "$licenses_source/freetype/LICENSE.TXT" "$notices_destination/FreeType-LICENSE.txt"
cp "$licenses_source/fribidi/COPYING" "$notices_destination/FriBidi-COPYING.txt"
cp "$licenses_source/harfbuzz/COPYING" "$notices_destination/HarfBuzz-COPYING.txt"
cp "$licenses_source/libass/COPYING" "$notices_destination/libass-COPYING.txt"
cp "$ffmpeg_licenses_source/COPYING.LGPLv2.1" "$notices_destination/FFmpeg-COPYING.LGPLv2.1.txt"
cp "$ffmpeg_licenses_source/LICENSE.md" "$notices_destination/FFmpeg-LICENSE.md"
cp "$model_license_source" "$notices_destination/Real-ESRGAN-LICENSE.txt"
ditto "$model_source" "$model_destination"

echo "Embedded verified FFmpeg helpers, restoration model, and third-party notices."
