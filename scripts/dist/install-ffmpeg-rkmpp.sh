#!/usr/bin/env bash
set -euo pipefail

# Installs FFmpeg.
# - On ARM64: builds Rockchip MPP + RGA + ffmpeg-rockchip from source and installs to /usr
# - Otherwise: keeps the existing behaviour (static builds)

PATH="/usr/local/sbin:/usr/sbin:/sbin:/usr/local/bin:/usr/bin:/bin:/scripts:$PATH"

# Show usage information if first argument is --help.
if [[ ${1:-} == "--help" ]]; then
  echo "Installs FFmpeg. On ARM64 builds Rockchip ffmpeg-rockchip; otherwise installs static builds." 1>&2
  echo "Usage: ${0##*/} [destdir] [version]" 1>&2
  exit 0
fi

# You can provide a custom installation directory as the first argument.
DESTDIR="$(realpath "${1:-/opt/ffmpeg}")"

# In addition, you can specify a custom version as the second argument.
FFMPEG_VERSION="${2:-release}"

# Determine target architecture.
if [[ ${PHOTOPRISM_ARCH:-} ]]; then
  SYSTEM_ARCH="$PHOTOPRISM_ARCH"
else
  SYSTEM_ARCH="$(uname -m)"
fi

DESTARCH="${BUILD_ARCH:-$SYSTEM_ARCH}"

case "$DESTARCH" in
  amd64|AMD64|x86_64|x86-64) DESTARCH="amd64" ;;
  arm64|ARM64|aarch64)       DESTARCH="arm64" ;;
  arm|ARM|aarch|armv7l|armhf) DESTARCH="armhf" ;;
  *)
    echo "Unsupported Machine Architecture: \"$DESTARCH\"" 1>&2
    exit 1
    ;;
esac

# shellcheck source=/dev/null
. /etc/os-release || true

echo "--------------------------------------------------------------------------------"
echo "ARCH:    $DESTARCH"
echo "VERSION: $FFMPEG_VERSION"
echo "DESTDIR: $DESTDIR"
echo "--------------------------------------------------------------------------------"

install_rockchip_ffmpeg_arm64() {
  echo "Installing Rockchip FFmpeg (ffmpeg-rockchip) for ARM64..."

  # Build dependencies (kept minimal; add more if your build complains)
  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates curl git \
    build-essential pkg-config \
    cmake meson ninja-build \
    yasm nasm \
    libdrm-dev \
    # common tooling
    python3 \
    && rm -rf /var/lib/apt/lists/*

  mkdir -p /tmp/dev
  cd /tmp/dev

  # --- Build MPP ---
  if [[ ! -d rkmpp ]]; then
    git clone -b jellyfin-mpp --depth=1 https://gitee.com/nyanmisaka/mpp.git rkmpp
  fi
  pushd rkmpp >/dev/null
  mkdir -p rkmpp_build
  pushd rkmpp_build >/dev/null
  cmake \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_TEST=OFF \
    ..
  make -j"$(nproc)"
  make install
  popd >/dev/null
  popd >/dev/null

  # --- Build RGA ---
  if [[ ! -d rkrga ]]; then
    git clone -b jellyfin-rga --depth=1 https://gitee.com/nyanmisaka/rga.git rkrga
  fi
  # meson setup wants separate build dir; follow the upstream guide closely
  meson setup rkrga rkrga_build \
    --prefix=/usr \
    --libdir=lib \
    --buildtype=release \
    --default-library=shared \
    -Dcpp_args=-fpermissive \
    -Dlibdrm=false \
    -Dlibrga_demo=false || true
  meson configure rkrga_build
  ninja -C rkrga_build install

  # --- Build FFmpeg (Rockchip fork) ---
  if [[ ! -d ffmpeg ]]; then
    git clone --depth=1 https://github.com/nyanmisaka/ffmpeg-rockchip.git ffmpeg
  fi
  pushd ffmpeg >/dev/null
  ./configure \
    --prefix=/usr \
    --enable-gpl --enable-version3 \
    --enable-libdrm --enable-rkmpp --enable-rkrga
  make -j"$(nproc)"
  make install
  popd >/dev/null

  # Refresh loader cache; ignore if ldconfig is missing (rare)
  command -v ldconfig >/dev/null 2>&1 && ldconfig || true

  # Make sure ffmpeg is on PATH where PhotoPrism expects it.
  ln -sf /usr/bin/ffmpeg /usr/local/bin/ffmpeg

  echo "Rockchip FFmpeg installed."
  /usr/bin/ffmpeg -hide_banner -version | head -n 1 || true
  /usr/bin/ffmpeg -hide_banner -encoders | grep -i rkmpp || true
  /usr/bin/ffmpeg -hide_banner -filters  | grep -i rkrga || true
}

install_static_ffmpeg() {
  echo "Installing static FFmpeg..."

  if [[ $FFMPEG_VERSION == "latest" ]] && [[ $DESTARCH == "amd64" ]]; then
    ARCHIVE="ffmpeg-master-${FFMPEG_VERSION}-linux64-gpl.tar.xz"
    URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/${ARCHIVE}"
  elif [[ $FFMPEG_VERSION == "latest" ]] && [[ $DESTARCH == "arm64" ]]; then
    ARCHIVE="ffmpeg-master-${FFMPEG_VERSION}-linuxarm64-gpl.tar.xz"
    URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/${ARCHIVE}"
  else
    ARCHIVE="ffmpeg-${FFMPEG_VERSION}-${DESTARCH}-static.tar.xz"
    URL="https://johnvansickle.com/ffmpeg/releases/${ARCHIVE}"
    DESTDIR="${DESTDIR}/bin"
  fi

  echo "Extracting \"$URL\" to \"$DESTDIR\"."
  mkdir -p "${DESTDIR}"
  curl -fsSL "$URL" | tar --strip-components=1 --overwrite --mode=755 -x --xz -C "$DESTDIR"
  chown -R root:root "${DESTDIR}"

  # Create a symbolic link to the static ffmpeg binary.
  ln -sf "${DESTDIR}/bin/ffmpeg" /usr/local/bin/ffmpeg

  echo "Done."
}

if [[ "$DESTARCH" == "arm64" ]]; then
  install_rockchip_ffmpeg_arm64
else
  install_static_ffmpeg
fi