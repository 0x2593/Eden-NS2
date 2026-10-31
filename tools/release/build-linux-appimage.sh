#!/usr/bin/env bash
# Builds an Eden-NS2 release for Linux and packages it as an AppImage.
#
# Made for Ubuntu 24.04 (also inside WSL on Windows), run from anywhere:
#   tools/release/build-linux-appimage.sh [--install-deps] [version]
# --install-deps installs the build packages with apt (needs sudo). Qt 6.8.3 is installed with
# aqtinstall and linuxdeploy is downloaded, both into .cache/ of the repository. The version (for
# example v1.0) is shown in the window title and used in the file name; without it the commit hash
# is used. The result is build-release-linux/Eden-NS2-<version>-x86_64.AppImage. It bundles every
# library the emulator needs except the base system ones (glibc, X11/Wayland, the GPU driver and
# Vulkan loader), so it runs on systems with glibc 2.39 or newer.
#
# Environment: JOBS (parallel compile jobs, default: all cores), BUILD_DIR (default
# build-release-linux), SKIP_BUILD=1 (only package an existing build).
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
install_deps=0
version=
for argument in "$@"; do
    case "$argument" in
        --install-deps) install_deps=1 ;;
        -*) echo "Unknown option $argument" >&2; exit 1 ;;
        *) version=$argument ;;
    esac
done
build=${BUILD_DIR:-"$root/build-release-linux"}
jobs=${JOBS:-$(nproc)}
cache="$root/.cache"
qt_version=6.8.3
qt_dir="$cache/qt/$qt_version/gcc_64"

if [[ $install_deps == 1 ]]; then
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends \
        autoconf build-essential ca-certificates cmake curl file g++ gcc git glslang-tools \
        libasound2-dev libavcodec-dev libavfilter-dev libavutil-dev libboost-context-dev \
        libboost-dev libboost-fiber-dev libegl1-mesa-dev libgl1-mesa-dev libglu1-mesa-dev \
        libopus-dev libpulse-dev libssl-dev libswscale-dev libtool libudev-dev libusb-1.0-0-dev \
        libva-dev libvdpau-dev libxkbcommon-x11-0 libxcb-cursor0 libxcb-icccm4 libxcb-image0 \
        libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 libxcb-shape0 libxcb-xinerama0 \
        libxcb-xkb1 mesa-common-dev nasm ninja-build patch pkg-config python3-venv spirv-headers \
        spirv-tools zlib1g-dev
fi

# Qt from the Qt installer's packages: the distribution's Qt (6.4 on Ubuntu 24.04) is too old.
if [[ ! -x "$qt_dir/bin/qmake" ]]; then
    python3 -m venv "$cache/aqt-venv"
    "$cache/aqt-venv/bin/pip" install --quiet aqtinstall
    "$cache/aqt-venv/bin/aqt" install-qt linux desktop "$qt_version" linux_gcc_64 \
        -m qtcharts -O "$cache/qt"
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
        -DYUZU_TESTS=OFF -DENABLE_WERROR=OFF -DYUZU_ROOM=OFF -DYUZU_ROOM_STANDALONE=OFF \
        -DYUZU_CMD=OFF -DENABLE_UPDATE_CHECKER=OFF -DUSE_DISCORD_PRESENCE=OFF \
        -DYUZU_USE_BUNDLED_QT=OFF -DCMAKE_PREFIX_PATH="$qt_dir" -DYUZU_USE_BUNDLED_SDL3=ON \
        -DVulkanHeaders_FORCE_BUNDLED=ON -DVulkanUtilityLibraries_FORCE_BUNDLED=ON \
        -DVulkanMemoryAllocator_FORCE_BUNDLED=ON -Denet_FORCE_BUNDLED=ON \
        -DCPM_SOURCE_CACHE="$cache/cpm"
    ninja -C "$build" -j "$jobs" yuzu
fi
test -x "$build/bin/eden"

tools="$cache/linuxdeploy"
mkdir -p "$tools"
for tool in linuxdeploy linuxdeploy-plugin-qt; do
    if [[ ! -x "$tools/$tool-x86_64.AppImage" ]]; then
        curl -fsSL -o "$tools/$tool-x86_64.AppImage" \
            "https://github.com/linuxdeploy/$tool/releases/download/continuous/$tool-x86_64.AppImage"
        chmod +x "$tools/$tool-x86_64.AppImage"
    fi
done

package="$build/package"
rm -rf "$package"
mkdir -p "$package"
# The desktop entry and icon keep Eden's id (dev.eden_emu.eden); only the shown name changes.
sed 's/^Name=.*/Name=Eden-NS2/' "$root/dist/dev.eden_emu.eden.desktop" > "$package/dev.eden_emu.eden.desktop"
cp "$root/dist/dev.eden_emu.eden.svg" "$package/dev.eden_emu.eden.svg"

name="Eden-NS2-${version:-$(git -C "$root" rev-parse --short=10 HEAD)}-x86_64.AppImage"
export APPIMAGE_EXTRACT_AND_RUN=1 # no FUSE needed (WSL, containers)
export QMAKE="$qt_dir/bin/qmake"
export LD_LIBRARY_PATH="$qt_dir/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LDAI_OUTPUT="$build/$name"
rm -f "$LDAI_OUTPUT"
(cd "$package" && "$tools/linuxdeploy-x86_64.AppImage" --appdir AppDir \
    --executable "$build/bin/eden" \
    --desktop-file "$package/dev.eden_emu.eden.desktop" \
    --icon-file "$package/dev.eden_emu.eden.svg" \
    --plugin qt --output appimage)
test -s "$LDAI_OUTPUT"
echo "Packaged $LDAI_OUTPUT ($(du -sh "$LDAI_OUTPUT" | cut -f1))"
