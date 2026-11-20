#!/usr/bin/env bash
# Fetches the reviewed Aether Android release and verifies locally pinned SHA-256 values.
# Updating AETHER_VERSION requires reviewing upstream release notes and all three checksums here.
set -euo pipefail
cd "$(dirname "$0")"
readonly AETHER_VERSION=2.4.0
readonly base="https://github.com/CluvexStudio/Aether/releases/download/v$AETHER_VERSION"
readonly checksums='02f1a1d673cf2f3e5592c90ce7ef4d6f03e218d41a333bdd175e0da92ce2073c  aether-android-arm64.tar.gz
13a170d175eab5a64d69c6fa3c174430754f01171d616a00eba0b3598315da1d  aether-android-armv7.tar.gz
b8d18baf6b1efe120d04109f819d08ca822c1fafeb3d61297b0e035cf095ae07  aether-android-x86_64.tar.gz'
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

for pair in arm64:arm64-v8a armv7:armeabi-v7a x86_64:x86_64; do
  arch=${pair%%:*} abi=${pair##*:} f=aether-android-$arch.tar.gz
  curl --proto '=https' --tlsv1.2 -fsSL --retry 3 -o "$tmp/$f" "$base/$f"
  expected=$(printf '%s\n' "$checksums" | awk -v f="$f" '$2 == f {print $1}')
  [ -n "$expected" ] || { echo "missing pinned checksum for $f" >&2; exit 1; }
  printf '%s  %s\n' "$expected" "$tmp/$f" | sha256sum -c --quiet
  mkdir -p "$tmp/$arch" android/app/src/main/jniLibs/$abi
  tar -xzf "$tmp/$f" -C "$tmp/$arch"
  aether=$(find "$tmp/$arch" -type f -name aether -print -quit)
  [ -n "$aether" ] || { echo "aether missing from $f" >&2; exit 1; }
  install -m 755 "$aether" android/app/src/main/jniLibs/$abi/libaether.so
  # Tor transport and Psiphon are executed by Aether from the native library directory.
  install -m 755 "$tmp/$arch/pt/lyrebird" android/app/src/main/jniLibs/$abi/liblyrebird.so
  install -m 755 "$tmp/$arch/pt/psiphon-tunnel-core" android/app/src/main/jniLibs/$abi/libpsiphon.so
  echo "Aether v$AETHER_VERSION $abi verified"
done
printf 'aether=%s\n' "$AETHER_VERSION" > android/app/src/main/jniLibs/NATIVE_VERSIONS.txt
printf 'hev-socks5-tunnel=%s\n' '2.17.1' >> android/app/src/main/jniLibs/NATIVE_VERSIONS.txt
printf '%s\n' "$checksums" > android/app/src/main/jniLibs/AETHER_SHA256SUMS.txt

# tun2socks for the VPN (AetherVpn.kt), built with the NDK into jniLibs as libhev-socks5-tunnel.so.
# JNI natives get registered on com.aether.aether_gui.AetherVpn via PKGNAME/CLSNAME.
git -c advice.detachedHead=false clone -q --depth 1 --branch 2.17.1 --recursive --shallow-submodules https://github.com/heiher/hev-socks5-tunnel "$tmp/hev"
# Windows git without symlink rights checks symlinks out as text files holding the target: copy the target in.
for repo in "$tmp/hev" $(git -C "$tmp/hev" submodule foreach --recursive --quiet pwd); do
  git -C "$repo" ls-files -s | awk '$1==120000{print $4}' | while read -r l; do
    f=$repo/$l; [ -L "$f" ] || cp "$(dirname "$f")/$(cat "$f")" "$f"
  done
done
ndk=${ANDROID_NDK_HOME:-$(ls -d "${ANDROID_HOME:-$LOCALAPPDATA/Android/Sdk}"/ndk/* | tail -1)}
nb=$ndk/ndk-build; [ -f "$nb" ] || nb=$nb.cmd
"$nb" -C "$tmp/hev" -j4 NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=Android.mk NDK_APPLICATION_MK=Application.mk \
  APP_MODULES=hev-socks5-tunnel APP_ABI="arm64-v8a armeabi-v7a x86_64" \
  APP_CFLAGS="-O3 -DPKGNAME=com/aether/aether_gui -DCLSNAME=AetherVpn -DLWIP_ERRNO_STDINCLUDE=1" NDK_LIBS_OUT="$tmp/libs" # not jniLibs: ndk-build wipes its output dir, libaether.so included
for abi in arm64-v8a armeabi-v7a x86_64; do cp "$tmp/libs/$abi/libhev-socks5-tunnel.so" android/app/src/main/jniLibs/$abi/; done
echo "hev-socks5-tunnel ok"
