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
OUTPUT_DIR="$WORK_DIR/restored-clips/$SOURCE_STEM"
FRAME_DIR="$OUTPUT_DIR/source-frames"
RESTORED_FRAMES="$OUTPUT_DIR/processed-frames"
METADATA="$OUTPUT_DIR/source-metadata.json"
PARTIAL_OUTPUT="$OUTPUT_DIR/restored-test.partial.mp4"
FINAL_OUTPUT="$OUTPUT_DIR/restored-test.mp4"
TIMESTAMP="00:09:00"
DURATION="2.0"
FRAME_COUNT=48

if [[ ! -x "$VENV_PYTHON" || ! -d "$MODEL" ]]; then
    echo "Prepare the research model first with Scripts/prepare-restoration-model.sh" >&2
    exit 1
fi
if [[ -e "$PARTIAL_OUTPUT" || -e "$FINAL_OUTPUT" ]]; then
    echo "Refusing to replace an existing restored test output in $OUTPUT_DIR" >&2
    exit 1
fi

FFMPEG="${FFMPEG:-$(command -v ffmpeg || true)}"
FFPROBE="${FFPROBE:-$(command -v ffprobe || true)}"
if [[ -z "$FFMPEG" || -z "$FFPROBE" ]]; then
    echo "Development FFmpeg and FFprobe builds are required." >&2
    exit 1
fi

mkdir -p "$FRAME_DIR" "$RESTORED_FRAMES"
"$FFPROBE" -v error -select_streams v:0 \
    -show_entries stream=codec_type,width,height,pix_fmt,color_range,color_space,color_transfer,color_primaries,sample_aspect_ratio,avg_frame_rate \
    -of json "$SOURCE" > "$METADATA"
FRAME_RATE="$("$FFPROBE" -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 "$SOURCE")"

"$FFMPEG" -hide_banner -loglevel error -ss "$TIMESTAMP" -i "$SOURCE" \
    -map 0:v:0 -frames:v "$FRAME_COUNT" -fps_mode passthrough -pix_fmt rgb24 -y \
    "$FRAME_DIR/frame-%04d.png"
frames=("$FRAME_DIR"/frame-*.png)
if [[ ${#frames[@]} -ne $FRAME_COUNT ]]; then
    echo "Expected $FRAME_COUNT source frames; found ${#frames[@]}." >&2
    exit 1
fi

LOCAL_TEMP="$(mktemp -d /tmp/swiftytranscoder-restored-clip.XXXXXX)"
trap 'rm -rf "$LOCAL_TEMP"' EXIT
ditto "$MODEL" "$LOCAL_TEMP/RealESRGAN_x2plus.mlpackage"
"$VENV_PYTHON" "$SCRIPT_DIR/process-restoration-sequence.py" \
    --model "$LOCAL_TEMP/RealESRGAN_x2plus.mlpackage" \
    --metadata "$METADATA" \
    --output "$RESTORED_FRAMES" \
    "${frames[@]}"

"$FFMPEG" -hide_banner -loglevel error \
    -framerate "$FRAME_RATE" -i "$RESTORED_FRAMES/frame-%04d-real-esrgan.png" \
    -ss "$TIMESTAMP" -t "$DURATION" -i "$SOURCE" \
    -map 0:v:0 -map 1:a:0 -map_metadata 1 \
    -vf "setparams=range=limited:color_primaries=smpte170m:color_trc=bt709:colorspace=smpte170m" \
    -c:v hevc_videotoolbox -allow_sw 0 -profile:v main -b:v 4000k \
    -tag:v hvc1 -pix_fmt yuv420p \
    -color_range tv -colorspace smpte170m -color_trc bt709 -color_primaries smpte170m \
    -af "volume=6dB,alimiter=limit=0.630957:level=false:latency=true" \
    -c:a ac3 -b:a 192k -ar 48000 -ac 2 \
    -frames:v "$FRAME_COUNT" -shortest -movflags +faststart "$PARTIAL_OUTPUT"

"$VENV_PYTHON" "$SCRIPT_DIR/validate-restored-test-clip.py" \
    --ffprobe "$FFPROBE" --expected-duration "$DURATION" "$PARTIAL_OUTPUT"
mv "$PARTIAL_OUTPUT" "$FINAL_OUTPUT"

echo "Restored test clip: $FINAL_OUTPUT"
