#!/bin/bash

set -euo pipefail

ffmpeg_version="9.0.2"
ffmpeg_sha256="8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"
ffmpeg_url="https://ffmpeg.org/releases/ffmpeg-${ffmpeg_version}.tar.xz"

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
work_root="$project_root/.build/toolchain"
archive="$work_root/ffmpeg-${ffmpeg_version}.tar.xz"
source_dir="$work_root/ffmpeg-${ffmpeg_version}"
install_dir="$work_root/stage"
dependency_dir="$work_root/dependencies"
deployment_target="14.0"

for tool in curl shasum tar make clang pkg-config otool; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Required build tool is missing: $tool" >&2
        exit 1
    fi
done

mkdir -p "$work_root"

"$script_dir/build-subtitle-dependencies.sh"
export PKG_CONFIG_LIBDIR="$dependency_dir/lib/pkgconfig:$dependency_dir/share/pkgconfig"
export PKG_CONFIG_PATH=

if [[ ! -f "$archive" ]]; then
    echo "Downloading FFmpeg ${ffmpeg_version} source…"
    curl --fail --location --output "$archive" "$ffmpeg_url"
fi

actual_sha256="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
if [[ "$actual_sha256" != "$ffmpeg_sha256" ]]; then
    echo "FFmpeg source checksum does not match." >&2
    echo "Expected: $ffmpeg_sha256" >&2
    echo "Actual:   $actual_sha256" >&2
    exit 1
fi

if [[ ! -d "$source_dir" ]]; then
    tar -xf "$archive" -C "$work_root"
fi

rm -rf "$install_dir"
mkdir -p "$install_dir"

cd "$source_dir"
make distclean >/dev/null 2>&1 || true
export MACOSX_DEPLOYMENT_TARGET="$deployment_target"

echo "Configuring the narrow FFmpeg toolchain…"
./configure \
    --prefix="$install_dir" \
    --cc=clang \
    --arch=arm64 \
    --target-os=darwin \
    --extra-cflags="-I$dependency_dir/include -mmacosx-version-min=$deployment_target" \
    --extra-ldflags="-L$dependency_dir/lib -lc++ -mmacosx-version-min=$deployment_target -Wl,-headerpad_max_install_names" \
    --disable-debug \
    --disable-doc \
    --disable-network \
    --disable-autodetect \
    --disable-everything \
    --disable-shared \
    --enable-static \
    --pkg-config-flags=--static \
    --enable-ffmpeg \
    --enable-ffprobe \
    --enable-avcodec \
    --enable-avfilter \
    --enable-avformat \
    --enable-swresample \
    --enable-swscale \
    --enable-videotoolbox \
    --enable-zlib \
    --enable-libass \
    --enable-protocol=file,pipe \
    --enable-demuxer=matroska,mov \
    --enable-muxer=mp4 \
    --enable-decoder=h264,hevc,mjpeg,aac,ac3,eac3,dca,truehd,flac,mp3,opus,vorbis,alac,pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le,subrip,pgssub \
    --enable-encoder=hevc_videotoolbox,ac3,aac \
    --enable-parser=aac,aac_latm,ac3,h264,hevc,mpegaudio,opus,vorbis \
    --enable-bsf=aac_adtstoasc,extract_extradata,h264_mp4toannexb,hevc_mp4toannexb \
    --enable-filter=abuffer,abuffersink,aformat,alimiter,anull,aresample,buffer,buffersink,format,scale,setparams,subtitles,volume

echo "Building FFmpeg ${ffmpeg_version}…"
make -j"$(sysctl -n hw.logicalcpu)"
make install

mkdir -p "$install_dir/share/licenses/ffmpeg"
cp "$source_dir/COPYING.LGPLv2.1" "$install_dir/share/licenses/ffmpeg/"
cp "$source_dir/LICENSE.md" "$install_dir/share/licenses/ffmpeg/"

echo "Verifying required capabilities…"
ffmpeg_bin="$install_dir/bin/ffmpeg"
ffprobe_bin="$install_dir/bin/ffprobe"
test -x "$ffmpeg_bin"
test -x "$ffprobe_bin"

"$ffmpeg_bin" -hide_banner -encoders | grep -q 'hevc_videotoolbox'
"$ffmpeg_bin" -hide_banner -encoders | grep -q ' ac3 '
"$ffmpeg_bin" -hide_banner -encoders | grep -q ' aac '
"$ffmpeg_bin" -hide_banner -decoders | grep -q ' pgssub '
"$ffmpeg_bin" -hide_banner -filters | grep -q ' subtitles '
"$ffmpeg_bin" -hide_banner -filters | grep -q ' alimiter '
"$ffmpeg_bin" -hide_banner -filters | grep -q ' setparams '
"$ffprobe_bin" -hide_banner -version | grep -q "ffprobe version ${ffmpeg_version}"
"$ffmpeg_bin" -hide_banner -version | grep -q 'configuration:.*--disable-network.*--disable-everything.*--enable-libass'
"$ffmpeg_bin" -hide_banner -L | grep -q 'GNU Lesser General Public'

for helper in "$ffmpeg_bin" "$ffprobe_bin"; do
    if otool -L "$helper" | awk 'NR > 1 { print $1 }' | grep -Eq '^(/opt/homebrew|/usr/local)/'; then
        echo "A build-machine library path remains in $helper:" >&2
        otool -L "$helper" >&2
        exit 1
    fi
done

echo ""
echo "Staged toolchain is ready:"
echo "  $ffmpeg_bin"
echo "  $ffprobe_bin"
echo ""
echo "libass and its subtitle dependencies are statically included."
