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

mkdir -p "$helpers_destination" "$notices_destination"

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

echo "Embedded verified FFmpeg helpers and third-party notices."
