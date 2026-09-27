#!/bin/bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 source-video [timestamp ...]" >&2
    exit 2
fi

SOURCE="$1"
shift
if [[ ! -f "$SOURCE" ]]; then
    echo "Source video not found: $SOURCE" >&2
    exit 1
fi

TIMESTAMPS=("$@")
if [[ ${#TIMESTAMPS[@]} -eq 0 ]]; then
    TIMESTAMPS=("00:04:30" "00:09:00" "00:22:30" "00:31:30")
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$PROJECT_DIR/.build/restoration-evaluation"
VENV_PYTHON="$WORK_DIR/venv/bin/python"
MODEL="$WORK_DIR/converter/weights/RealESRGAN_x2plus_522_fp16.mlpackage"
SOURCE_NAME="$(basename "$SOURCE")"
SOURCE_STEM="${SOURCE_NAME%.*}"
OUTPUT_DIR="$WORK_DIR/comparisons/$SOURCE_STEM"
FRAME_DIR="$OUTPUT_DIR/source-frames"

if [[ ! -x "$VENV_PYTHON" || ! -d "$MODEL" ]]; then
    echo "Prepare the research model first with Scripts/prepare-restoration-model.sh" >&2
    exit 1
fi

FFMPEG="${FFMPEG:-$(command -v ffmpeg || true)}"
FFPROBE="${FFPROBE:-$(command -v ffprobe || true)}"
if [[ -z "$FFMPEG" || -z "$FFPROBE" ]]; then
    echo "Development FFmpeg and FFprobe builds with PNG support are required." >&2
    exit 1
fi
FFMPEG_FORMATS="$("$FFMPEG" -hide_banner -formats 2>/dev/null)"
if [[ "$FFMPEG_FORMATS" != *image2* ]]; then
    echo "The selected FFmpeg does not include PNG/image2 output support: $FFMPEG" >&2
    exit 1
fi

mkdir -p "$FRAME_DIR"
METADATA="$OUTPUT_DIR/source-metadata.json"
TIMESTAMP_MANIFEST="$OUTPUT_DIR/timestamps.txt"
"$FFPROBE" -v error -select_streams v:0 \
    -show_entries stream=codec_type,width,height,pix_fmt,color_range,color_space,color_transfer,color_primaries,sample_aspect_ratio \
    -of json "$SOURCE" > "$METADATA"

FRAMES=()
: > "$TIMESTAMP_MANIFEST"
index=1
for timestamp in "${TIMESTAMPS[@]}"; do
    frame="$FRAME_DIR/frame-$(printf '%02d' "$index").png"
    "$FFMPEG" -hide_banner -loglevel error -ss "$timestamp" -i "$SOURCE" \
        -map 0:v:0 -frames:v 1 -pix_fmt rgb24 -y "$frame"
    FRAMES+=("$frame")
    printf 'frame-%02d\t%s\n' "$index" "$timestamp" >> "$TIMESTAMP_MANIFEST"
    index=$((index + 1))
done

LOCAL_TEMP="$(mktemp -d /tmp/swiftytranscoder-comparison.XXXXXX)"
trap 'rm -rf "$LOCAL_TEMP"' EXIT
ditto "$MODEL" "$LOCAL_TEMP/RealESRGAN_x2plus.mlpackage"

"$VENV_PYTHON" "$SCRIPT_DIR/compare-restoration-frames.py" \
    --model "$LOCAL_TEMP/RealESRGAN_x2plus.mlpackage" \
    --metadata "$METADATA" \
    --output "$OUTPUT_DIR" \
    "${FRAMES[@]}"

echo "Comparisons: $OUTPUT_DIR"
