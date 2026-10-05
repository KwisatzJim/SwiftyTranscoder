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
sd_model_name="RealESRGAN_x2plus_656x384_fp16.mlpackage"
sd_model_source="$project_root/.build/restoration-evaluation/sd-shape-experiment/$sd_model_name"
sd_model_destination="$app_contents/Resources/Models/$sd_model_name"
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
verify_checksum "f7ab86b57d5bd1d2dc4b373e1ffbde5345cbc19059e85401d5f157873730eabf" "$sd_model_source/Manifest.json"
verify_checksum "21fc2a660891b7435418c3cb9d57eabd920d0e3f57440bdc8632efe4c50a7fd8" "$sd_model_source/Data/com.apple.CoreML/model.mlmodel"
verify_checksum "a8904f0bb627d5dbce2468a96c648764a63ece561cfcf118da6321831bb3a926" "$sd_model_source/Data/com.apple.CoreML/weights/weight.bin"

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
ditto "$sd_model_source" "$sd_model_destination"

# Accepted model choices are required in every app build, including releases.
fast_name="RealESRGAN_general_x2_522_fp16.mlpackage"
fast_source="$project_root/.build/restoration-evaluation/fast-candidate/$fast_name"
if [[ ! -d "$fast_source" ]]; then
    echo "error: Missing prepared compact model: $fast_source" >&2
    exit 1
fi
{
    verify_checksum "9878f924115d8c8e78610fc4b00029d827750bc0d96e9fb57eda9d6c1d540402" "$fast_source/Manifest.json"
    verify_checksum "f73dbe79485ee9ba81aede548a18fec2d39969f0b3ea5fc3f4e982bd5de22ded" "$fast_source/Data/com.apple.CoreML/model.mlmodel"
    verify_checksum "7a6088b2ee537938f380b9049fae2b85dad57b251d047ab8f5afd256417838ec" "$fast_source/Data/com.apple.CoreML/weights/weight.bin"
    ditto "$fast_source" "$app_contents/Resources/Models/$fast_name"
}

lightweight_name="FSRCNN_x2_RGB_522_fp16.mlpackage"
lightweight_root="$project_root/.build/restoration-evaluation/fsrcnn-candidate"
lightweight_source="$lightweight_root/$lightweight_name"
if [[ ! -d "$lightweight_source" || ! -f "$lightweight_root/LICENSE" ]]; then
    echo "error: Missing prepared FSRCNN model or license: $lightweight_root" >&2
    exit 1
fi
{
    verify_checksum "65bc1cb2d12c85e77f63f105e210f2b3fc011ccfebeffc7592289dc43fbcc4ee" "$lightweight_source/Manifest.json"
    verify_checksum "77e39276f595f522674022564346090bcd6fc17134dabd7ef3877c03fc9f531c" "$lightweight_source/Data/com.apple.CoreML/model.mlmodel"
    verify_checksum "d21b1ae5f2959fa4ea86fe69aa880fc71aefe612cef7a41efbb04e46716dbb60" "$lightweight_source/Data/com.apple.CoreML/weights/weight.bin"
    verify_checksum "c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4" "$lightweight_root/LICENSE"
    ditto "$lightweight_source" "$app_contents/Resources/Models/$lightweight_name"
    cp "$lightweight_root/LICENSE" "$notices_destination/FSRCNN-LICENSE.txt"
    echo "FSRCNN x2 weights: Saafke/FSRCNN_Tensorflow, https://github.com/Saafke/FSRCNN_Tensorflow. RGB Core ML adaptation by SwiftyTranscoder." > "$notices_destination/FSRCNN-Attribution.txt"
}

echo "Embedded verified FFmpeg helpers, restoration model, and third-party notices."
