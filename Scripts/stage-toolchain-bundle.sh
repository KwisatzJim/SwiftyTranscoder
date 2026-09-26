#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
toolchain_root="$project_root/.build/toolchain"
source_bin="$toolchain_root/stage/bin"
bundle_root="$toolchain_root/bundle/SwiftyTranscoderToolchain"
helpers_dir="$bundle_root/Contents/Helpers"
frameworks_dir="$bundle_root/Contents/Frameworks"
queue_file="$toolchain_root/bundle-queue.txt"
source_map="$toolchain_root/bundle-source-map.txt"
deployment_target="14.0"

for tool in otool vtool install_name_tool codesign awk sed basename dirname; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Required staging tool is missing: $tool" >&2
        exit 1
    fi
done

for helper in ffmpeg ffprobe; do
    if [[ ! -x "$source_bin/$helper" ]]; then
        echo "Missing staged $helper. Run Scripts/build-toolchain.sh first." >&2
        exit 1
    fi
done

case "$bundle_root" in
    "$project_root/.build/toolchain/bundle/SwiftyTranscoderToolchain") ;;
    *)
        echo "Refusing to replace unexpected bundle path: $bundle_root" >&2
        exit 1
        ;;
esac

rm -rf "$bundle_root"
mkdir -p "$helpers_dir" "$frameworks_dir"
cp "$source_bin/ffmpeg" "$source_bin/ffprobe" "$helpers_dir/"
chmod u+w "$helpers_dir/ffmpeg" "$helpers_dir/ffprobe"

printf '%s\n%s\n' "$helpers_dir/ffmpeg" "$helpers_dir/ffprobe" > "$queue_file"
: > "$source_map"
queue_index=1

while :; do
    item="$(sed -n "${queue_index}p" "$queue_file")"
    [[ -n "$item" ]] || break
    queue_index=$((queue_index + 1))

    dependencies_file="$toolchain_root/dependencies.txt"
    otool -L "$item" | awk 'NR > 1 { print $1 }' > "$dependencies_file"

    while IFS= read -r dependency; do
        case "$dependency" in
            /opt/homebrew/*|/usr/local/*)
                library_name="$(basename "$dependency")"
                destination="$frameworks_dir/$library_name"
                dependency_directory="$(cd "$(dirname "$dependency")" && pwd -P)"
                resolved_dependency="$dependency_directory/$library_name"

                if [[ ! -e "$destination" ]]; then
                    cp -L "$dependency" "$destination"
                    chmod u+w "$destination"
                    codesign --remove-signature "$destination" 2>/dev/null || true
                    printf '%s\n' "$destination" >> "$queue_file"
                    printf '%s|%s\n' "$library_name" "$resolved_dependency" >> "$source_map"
                else
                    recorded_source="$(awk -F '|' -v name="$library_name" '$1 == name { print $2; exit }' "$source_map")"
                    if [[ "$recorded_source" != "$resolved_dependency" ]]; then
                        echo "Two different libraries share the name $library_name." >&2
                        echo "  $recorded_source" >&2
                        echo "  $resolved_dependency" >&2
                        exit 1
                    fi
                fi

                install_name_tool -change "$dependency" "@rpath/$library_name" "$item"
                ;;
        esac
    done < "$dependencies_file"

    case "$item" in
        "$frameworks_dir"/*)
            install_name_tool -id "@rpath/$(basename "$item")" "$item"
            ;;
    esac
done

echo "Checking rewritten linkage…"
while IFS= read -r item; do
    if otool -L "$item" | awk 'NR > 1 { print $1 }' | grep -Eq '^(/opt/homebrew|/usr/local)/'; then
        echo "A build-machine library path remains in $item:" >&2
        otool -L "$item" >&2
        exit 1
    fi
done < "$queue_file"

echo "Signing staged libraries and helpers…"
find "$frameworks_dir" -type f -name '*.dylib' -print0 \
    | while IFS= read -r -d '' library; do
        codesign --force --sign - "$library"
        codesign --verify --strict "$library"
    done

for helper in "$helpers_dir/ffmpeg" "$helpers_dir/ffprobe"; do
    codesign --force --sign - "$helper"
    codesign --verify --strict "$helper"
done

runtime_log="$toolchain_root/bundled-runtime-libraries.txt"
DYLD_PRINT_LIBRARIES=1 "$helpers_dir/ffprobe" -hide_banner -version \
    >/dev/null 2>"$runtime_log"

if grep -Eq '^dyld.*(/opt/homebrew|/usr/local)/' "$runtime_log"; then
    echo "The bundled ffprobe loaded a library from Homebrew:" >&2
    cat "$runtime_log" >&2
    exit 1
fi

library_count="$(find "$frameworks_dir" -type f -name '*.dylib' | wc -l | tr -d ' ')"
bundle_size="$(du -sh "$bundle_root" | awk '{ print $1 }')"
incompatible_items=0

echo ""
echo "Linkage-complete proof bundle staged:"
echo "  $bundle_root"
echo "  $library_count bundled non-system libraries"
echo "  $bundle_size total size"

echo ""
echo "Checking the macOS $deployment_target deployment target…"
while IFS= read -r item; do
    minimum_version="$(vtool -show-build "$item" 2>/dev/null | awk '/minos/ { print $2; exit }')"
    if [[ -z "$minimum_version" ]] || ! awk -v minimum="$minimum_version" -v target="$deployment_target" \
        'BEGIN { exit !(minimum <= target) }'; then
        echo "  $(basename "$item") requires macOS ${minimum_version:-unknown}"
        incompatible_items=$((incompatible_items + 1))
    fi
done < "$queue_file"

if [[ $incompatible_items -ne 0 ]]; then
    echo "" >&2
    echo "This proof bundle is not release-compatible with macOS $deployment_target." >&2
    echo "Rebuild the listed libraries from pinned source before packaging them." >&2
    exit 1
fi

echo "All staged code supports macOS $deployment_target."
