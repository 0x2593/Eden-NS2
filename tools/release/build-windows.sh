#!/usr/bin/env bash
# Builds an Eden-NS2 release for Windows with MSYS2 MinGW64 and packages it as a zip.
#
# Run it in an MSYS2 MINGW64 shell (packages: see "Building (Windows, MSYS2 MINGW64)" in README.md):
#   tools/release/build-windows.sh [version]
# The version (for example v1.0) is shown in the window title and used in the zip's name; without
# it the commit hash is used. The result is build-release-windows/Eden-NS2-<version>-windows-x86_64.zip,
# a folder with eden.exe and every DLL and Qt plugin it needs.
#
# Environment: JOBS (parallel compile jobs, default: all cores), BUILD_DIR (default
# build-release-windows), SKIP_BUILD=1 (only package an existing build).
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
version=${1:-}
build=${BUILD_DIR:-"$root/build-release-windows"}
jobs=${JOBS:-$(nproc)}

if [[ "${MSYSTEM:-}" != MINGW64 ]]; then
    echo "Run this in an MSYS2 MINGW64 shell." >&2
    exit 1
fi

if [[ -z "${SKIP_BUILD:-}" ]]; then
    # GIT-TAG and GIT-RELEASE hand the version to CMake (externals/cmake-modules/GetSCMRev.cmake).
    trap 'rm -f "$root/GIT-TAG" "$root/GIT-RELEASE"' EXIT
    rm -f "$root/GIT-TAG" "$root/GIT-RELEASE"
    if [[ -n "$version" ]]; then
        printf '%s' "$version" > "$root/GIT-TAG"
        printf '%s' "$version" > "$root/GIT-RELEASE"
    fi
    cmake -S "$root" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
        -DYUZU_TESTS=OFF -DENABLE_WERROR=OFF -DYUZU_ROOM=OFF -DYUZU_CMD=OFF -DENABLE_LIBUSB=OFF \
        -DENABLE_UPDATE_CHECKER=OFF -DENABLE_QT_TRANSLATION=OFF -Denet_FORCE_BUNDLED=ON \
        -Dlibusb_FORCE_BUNDLED=ON -DVulkanMemoryAllocator_FORCE_BUNDLED=ON \
        -DCPM_SOURCE_CACHE="$root/.cache/cpm"
    ninja -C "$build" -j "$jobs" yuzu
fi

name="Eden-NS2-${version:-$(git -C "$root" rev-parse --short=10 HEAD)}-windows-x86_64"
package="$build/package"
stage="$package/$name"
rm -rf "$package"
mkdir -p "$stage"
cp "$build/bin/eden.exe" "$stage/"

# Qt: its libraries, plugins (platforms, styles, image formats, ...) and their folders.
windeployqt6 --release --no-translations --no-system-d3d-compiler --no-opengl-sw "$stage/eden.exe" > /dev/null

# Everything else the executable and the Qt plugins load from MinGW (FFmpeg, SDL3, OpenSSL, the
# C++ runtime, ...), followed until no new DLL turns up.
while true; do
    added=0
    while IFS= read -r dll; do
        if [[ ! -e "$stage/$(basename "$dll")" ]]; then
            cp "$dll" "$stage/"
            added=1
        fi
    done < <(find "$stage" -name '*.exe' -o -name '*.dll' | while IFS= read -r binary; do
                 ldd "$binary" | awk '$3 ~ /^\/mingw64\// { print $3 }'
             done | sort -u)
    [[ $added == 0 ]] && break
done

cp "$root/LICENSE.txt" "$root/README.md" "$stage/"

# Windows' own tar writes zip archives (MSYS2's does not).
rm -f "$build/$name.zip"
(cd "$package" && "$(cygpath -u "$SYSTEMROOT")/System32/tar.exe" -a -cf "../$name.zip" "$name")
echo "Packaged $build/$name.zip ($(du -sh "$build/$name.zip" | cut -f1))"
