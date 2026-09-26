#!/bin/bash

set -euo pipefail

deployment_target="14.0"
freetype_version="2.14.3"
freetype_sha256="36bc4f1cc413335368ee656c42afca65c5a3987e8768cc28cf11ba775e785a5f"
fribidi_version="1.0.17"
fribidi_sha256="6949dcde27d41cebad1fd741fcafc36d55a1020d2d872d4a6eb3914caabbada2"
harfbuzz_version="14.5.0"
harfbuzz_sha256="b7132e148358a45185c9feafd049dbaf243649d3c44414b3534d9c95d18592b9"
libass_version="0.17.5"
libass_sha256="2dca25c0e0c837ddf00b52011b3f82cac1e4ddd3ad018227806b0c2288864acc"

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
toolchain_root="$project_root/.build/toolchain"
source_root="$toolchain_root/dependency-sources"
build_root="$toolchain_root/dependency-build"
install_dir="$toolchain_root/dependencies"

for tool in curl shasum tar cmake make clang pkg-config; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Required dependency build tool is missing: $tool" >&2
        exit 1
    fi
done

download_and_verify() {
    local name="$1"
    local version="$2"
    local url="$3"
    local expected_sha256="$4"
    local archive="$source_root/${name}-${version}.tar.xz"

    if [[ ! -f "$archive" ]]; then
        echo "Downloading ${name} ${version}…"
        curl --fail --location --output "$archive" "$url"
    fi

    local actual_sha256
    actual_sha256="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        echo "${name} source checksum does not match." >&2
        echo "Expected: $expected_sha256" >&2
        echo "Actual:   $actual_sha256" >&2
        exit 1
    fi
}

mkdir -p "$source_root" "$build_root"

download_and_verify \
    freetype "$freetype_version" \
    "https://downloads.sourceforge.net/project/freetype/freetype2/${freetype_version}/freetype-${freetype_version}.tar.xz" \
    "$freetype_sha256"
download_and_verify \
    fribidi "$fribidi_version" \
    "https://github.com/fribidi/fribidi/releases/download/v${fribidi_version}/fribidi-${fribidi_version}.tar.xz" \
    "$fribidi_sha256"
download_and_verify \
    harfbuzz "$harfbuzz_version" \
    "https://github.com/harfbuzz/harfbuzz/releases/download/${harfbuzz_version}/harfbuzz-${harfbuzz_version}.tar.xz" \
    "$harfbuzz_sha256"
download_and_verify \
    libass "$libass_version" \
    "https://github.com/libass/libass/releases/download/${libass_version}/libass-${libass_version}.tar.xz" \
    "$libass_sha256"

case "$toolchain_root" in
    "$project_root/.build/toolchain") ;;
    *)
        echo "Refusing to replace unexpected toolchain path: $toolchain_root" >&2
        exit 1
        ;;
esac

rm -rf "$build_root" "$install_dir"
mkdir -p "$build_root" "$install_dir"

for name_and_version in \
    "freetype-$freetype_version" \
    "fribidi-$fribidi_version" \
    "harfbuzz-$harfbuzz_version" \
    "libass-$libass_version"; do
    source_dir="$source_root/$name_and_version"
    rm -rf "$source_dir"
    tar -xf "$source_root/${name_and_version}.tar.xz" -C "$source_root"
done

export MACOSX_DEPLOYMENT_TARGET="$deployment_target"
export CC=clang
export CXX=clang++
export CFLAGS="-O2 -mmacosx-version-min=$deployment_target"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-mmacosx-version-min=$deployment_target"
export PKG_CONFIG_LIBDIR="$install_dir/lib/pkgconfig:$install_dir/share/pkgconfig"
export PKG_CONFIG_PATH=

echo "Building static FreeType ${freetype_version}…"
cmake \
    -S "$source_root/freetype-$freetype_version" \
    -B "$build_root/freetype" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install_dir" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
    -DBUILD_SHARED_LIBS=OFF \
    -DFT_DISABLE_ZLIB=TRUE \
    -DFT_DISABLE_BZIP2=TRUE \
    -DFT_DISABLE_PNG=TRUE \
    -DFT_DISABLE_HARFBUZZ=TRUE \
    -DFT_DISABLE_BROTLI=TRUE
cmake --build "$build_root/freetype" --parallel "$(sysctl -n hw.logicalcpu)"
cmake --install "$build_root/freetype"

echo "Building static FriBidi ${fribidi_version}…"
mkdir -p "$build_root/fribidi"
(
    cd "$build_root/fribidi"
    "$source_root/fribidi-$fribidi_version/configure" \
        --prefix="$install_dir" \
        --disable-shared \
        --enable-static \
        --disable-deprecated
    make -C lib -j"$(sysctl -n hw.logicalcpu)"
    make -C lib install
    mkdir -p "$install_dir/lib/pkgconfig"
    cp fribidi.pc "$install_dir/lib/pkgconfig/"
)

echo "Building static HarfBuzz ${harfbuzz_version}…"
cmake \
    -S "$source_root/harfbuzz-$harfbuzz_version" \
    -B "$build_root/harfbuzz" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install_dir" \
    -DCMAKE_PREFIX_PATH="$install_dir" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
    -DBUILD_SHARED_LIBS=OFF \
    -DHB_HAVE_FREETYPE=ON \
    -DHB_HAVE_CORETEXT=ON \
    -DHB_HAVE_CAIRO=OFF \
    -DHB_HAVE_GLIB=OFF \
    -DHB_HAVE_GOBJECT=OFF \
    -DHB_HAVE_GRAPHITE2=OFF \
    -DHB_HAVE_ICU=OFF \
    -DHB_BUILD_UTILS=OFF \
    -DHB_BUILD_SUBSET=OFF \
    -DHB_BUILD_RASTER=OFF \
    -DHB_BUILD_VECTOR=OFF \
    -DHB_BUILD_GPU=OFF
cmake --build "$build_root/harfbuzz" --parallel "$(sysctl -n hw.logicalcpu)"
cmake --install "$build_root/harfbuzz"

echo "Building static libass ${libass_version}…"
mkdir -p "$build_root/libass"
(
    cd "$build_root/libass"
    "$source_root/libass-$libass_version/configure" \
        --prefix="$install_dir" \
        --disable-shared \
        --enable-static \
        --disable-fontconfig \
        --disable-libunibreak \
        --enable-require-system-font-provider
    make -j"$(sysctl -n hw.logicalcpu)"
    make install
)

licenses_dir="$install_dir/share/licenses"
mkdir -p \
    "$licenses_dir/freetype" \
    "$licenses_dir/fribidi" \
    "$licenses_dir/harfbuzz" \
    "$licenses_dir/libass"
cp "$source_root/freetype-$freetype_version/LICENSE.TXT" "$licenses_dir/freetype/"
cp "$source_root/fribidi-$fribidi_version/COPYING" "$licenses_dir/fribidi/"
cp "$source_root/harfbuzz-$harfbuzz_version/COPYING" "$licenses_dir/harfbuzz/"
cp "$source_root/libass-$libass_version/COPYING" "$licenses_dir/libass/"

for library in libfreetype.a libfribidi.a libharfbuzz.a libass.a; do
    if [[ ! -f "$install_dir/lib/$library" ]]; then
        echo "Expected static library was not installed: $library" >&2
        exit 1
    fi
done

if find "$install_dir/lib" -type f -name '*.dylib' | grep -q .; then
    echo "An unexpected dynamic library was installed:" >&2
    find "$install_dir/lib" -type f -name '*.dylib' >&2
    exit 1
fi

echo ""
echo "Static subtitle dependencies are ready:"
echo "  $install_dir"
