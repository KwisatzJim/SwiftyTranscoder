#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 source-video" >&2
    exit 2
fi

SOURCE="$1"
if [[ ! -f "$SOURCE" ]]; then
    echo "Source video not found: $SOURCE" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$PROJECT_DIR/.build/restoration-evaluation"
VENV_PYTHON="$WORK_DIR/venv/bin/python"
MODEL="$WORK_DIR/converter/weights/RealESRGAN_x2plus_522_fp16.mlpackage"
SOURCE_NAME="$(basename "$SOURCE")"
SOURCE_STEM="${SOURCE_NAME%.*}"
OUTPUT_DIR="$WORK_DIR/clip-comparisons/$SOURCE_STEM"

if [[ ! -x "$VENV_PYTHON" || ! -d "$MODEL" ]]; then
    echo "Prepare the research model first with Scripts/prepare-restoration-model.sh" >&2
    exit 1
fi

FFMPEG="${FFMPEG:-$(command -v ffmpeg || true)}"
FFPROBE="${FFPROBE:-$(command -v ffprobe || true)}"
if [[ -z "$FFMPEG" || -z "$FFPROBE" ]]; then
    echo "Development FFmpeg and FFprobe builds with PNG and H.264 support are required." >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
METADATA="$OUTPUT_DIR/source-metadata.json"
"$FFPROBE" -v error -select_streams v:0 \
    -show_entries stream=codec_type,width,height,pix_fmt,color_range,color_space,color_transfer,color_primaries,sample_aspect_ratio,avg_frame_rate \
    -of json "$SOURCE" > "$METADATA"
FRAME_RATE="$("$FFPROBE" -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 "$SOURCE")"

NAMES=("credits" "face" "motion-graphics" "dark")
TIMESTAMPS=("00:04:30" "00:09:00" "00:22:30" "00:31:30")
FRAME_COUNT=24
LOCAL_TEMP="$(mktemp -d /tmp/swiftytranscoder-clips.XXXXXX)"
trap 'rm -rf "$LOCAL_TEMP"' EXIT
ditto "$MODEL" "$LOCAL_TEMP/RealESRGAN_x2plus.mlpackage"

for index in "${!NAMES[@]}"; do
    name="${NAMES[$index]}"
    timestamp="${TIMESTAMPS[$index]}"
    clip_dir="$OUTPUT_DIR/$name"
    frame_dir="$clip_dir/source-frames"
    mkdir -p "$frame_dir"
    "$FFMPEG" -hide_banner -loglevel error -ss "$timestamp" -i "$SOURCE" \
        -map 0:v:0 -frames:v "$FRAME_COUNT" -fps_mode passthrough -pix_fmt rgb24 -y \
        "$frame_dir/frame-%04d.png"

    frames=("$frame_dir"/frame-*.png)
    if [[ ${#frames[@]} -ne $FRAME_COUNT ]]; then
        echo "Expected $FRAME_COUNT frames for $name; found ${#frames[@]}." >&2
        exit 1
    fi
    "$VENV_PYTHON" "$SCRIPT_DIR/process-restoration-sequence.py" \
        --model "$LOCAL_TEMP/RealESRGAN_x2plus.mlpackage" \
        --metadata "$METADATA" \
        --output "$clip_dir" \
        "${frames[@]}"

    "$FFMPEG" -hide_banner -loglevel error \
        -framerate "$FRAME_RATE" -i "$clip_dir/frame-%04d-comparison.png" \
        -frames:v "$FRAME_COUNT" -c:v libx264 -crf 18 -pix_fmt yuv420p \
        -movflags +faststart -y "$clip_dir/comparison.mp4"
done

echo "Clip comparisons: $OUTPUT_DIR"
