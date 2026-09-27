#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$PROJECT_DIR/.build/restoration-evaluation"
DOWNLOAD_DIR="$WORK_DIR/downloads"
CONVERTER_DIR="$WORK_DIR/converter"
VENV_DIR="$WORK_DIR/venv"
MODEL_NAME="RealESRGAN_x2plus_522_fp16.mlpackage"
MODEL_PATH="$CONVERTER_DIR/weights/$MODEL_NAME"
LICENSE_DIR="$WORK_DIR/licenses"

WEIGHTS_URL="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth"
WEIGHTS_SHA256="49fafd45f8fd7aa8d31ab2a22d14d91b536c34494a5cfe31eb5d89c2fa266abb"
CONVERTER_COMMIT="88b473f383bd69e0e52ea1f266e6585c4fab34bf"
CONVERTER_URL="https://raw.githubusercontent.com/hanxiao/real-esrgan-coreml/$CONVERTER_COMMIT/convert.py"
CONVERTER_SHA256="152404e3021958c6e51edcde9fd17f2757ccf15f0e0d4e5c485495fd852b4af4"
LICENSE_URL="https://raw.githubusercontent.com/xinntao/Real-ESRGAN/v0.2.1/LICENSE"
LICENSE_SHA256="4a699ec4863d96a91fc265948a0c90033f7e8735d515524dcf3444736406e0c2"
MANIFEST_SHA256="6f4af8152eba8589bee31c7fe341a5b35534f06330056606a6df099589395790"
MODEL_SHA256="b79575977211ba89fb7856076e652fdd34f822b5228858e15b8d61169720e1ac"
MODEL_WEIGHTS_SHA256="a8904f0bb627d5dbce2468a96c648764a63ece561cfcf118da6321831bb3a926"

verify_checksum() {
    local expected="$1"
    local file="$2"
    local actual
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        echo "Checksum mismatch for $file" >&2
        echo "Expected: $expected" >&2
        echo "Actual:   $actual" >&2
        exit 1
    fi
}

download_verified() {
    local url="$1"
    local expected="$2"
    local destination="$3"
    if [[ ! -f "$destination" ]]; then
        curl -L --fail --show-error "$url" -o "$destination"
    fi
    verify_checksum "$expected" "$destination"
}

PYTHON="${PYTHON:-$(command -v python3.12 || true)}"
if [[ -z "$PYTHON" ]]; then
    echo "Python 3.12 is required to prepare this research model." >&2
    exit 1
fi

mkdir -p "$DOWNLOAD_DIR" "$CONVERTER_DIR/weights" "$LICENSE_DIR"

WEIGHTS_PATH="$DOWNLOAD_DIR/RealESRGAN_x2plus.pth"
ORIGINAL_CONVERTER="$DOWNLOAD_DIR/convert-$CONVERTER_COMMIT.py"
download_verified "$WEIGHTS_URL" "$WEIGHTS_SHA256" "$WEIGHTS_PATH"
download_verified "$CONVERTER_URL" "$CONVERTER_SHA256" "$ORIGINAL_CONVERTER"
download_verified "$LICENSE_URL" "$LICENSE_SHA256" "$LICENSE_DIR/Real-ESRGAN-LICENSE.txt"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    "$PYTHON" -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/python" -m pip install \
    coremltools==9.0 \
    numpy==2.2.6 \
    pillow==12.3.0 \
    torch==2.7.0

if [[ "$(grep -c 'ct.target.macOS15' "$ORIGINAL_CONVERTER")" != "1" ]]; then
    echo "The pinned converter no longer contains the expected deployment target." >&2
    exit 1
fi
sed 's/ct\.target\.macOS15/ct.target.macOS14/' "$ORIGINAL_CONVERTER" > "$CONVERTER_DIR/convert.py"
cp "$WEIGHTS_PATH" "$CONVERTER_DIR/weights/RealESRGAN_x2plus.pth"

if [[ ! -d "$MODEL_PATH" ]]; then
    "$VENV_DIR/bin/python" "$CONVERTER_DIR/convert.py" --model x2plus --size 522
fi

verify_checksum "$MANIFEST_SHA256" "$MODEL_PATH/Manifest.json"
verify_checksum "$MODEL_SHA256" "$MODEL_PATH/Data/com.apple.CoreML/model.mlmodel"
verify_checksum "$MODEL_WEIGHTS_SHA256" "$MODEL_PATH/Data/com.apple.CoreML/weights/weight.bin"

# Apple's compiler needs its source and output on the local startup disk. It
# fails with a misleading permission error when compiling from some external
# volumes, so validation uses a private temporary directory.
LOCAL_TEMP="$(mktemp -d /tmp/swiftytranscoder-restoration.XXXXXX)"
trap 'rm -rf "$LOCAL_TEMP"' EXIT
ditto "$MODEL_PATH" "$LOCAL_TEMP/$MODEL_NAME"
mkdir "$LOCAL_TEMP/compiled"
xcrun coremlcompiler compile \
    "$LOCAL_TEMP/$MODEL_NAME" \
    "$LOCAL_TEMP/compiled" \
    --platform macOS \
    --deployment-target 14.0

"$VENV_DIR/bin/python" "$SCRIPT_DIR/evaluate-restoration-model.py" \
    "$LOCAL_TEMP/$MODEL_NAME"

echo
echo "Restoration candidate preparation: PASS"
echo "Research model: $MODEL_PATH"
echo "The prepared model remains ignored; verified application builds embed it as a resource."
