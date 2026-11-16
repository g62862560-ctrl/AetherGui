#!/usr/bin/env bash
# Downloads the Windows TUN helper for AetherGui (tun2socks + Wintun), verified against published SHA-256.
set -euo pipefail
cd "$(dirname "$0")"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/tun2socks.zip" https://github.com/xjasonlyu/tun2socks/releases/download/v2.7.0/tun2socks-windows-amd64.zip
echo "c5d46e9452f6c9cc7c15ab9158d6d6a0169ceecd6bca019ce476b49337d2be43  $tmp/tun2socks.zip" | sha256sum -c --quiet
unzip -q "$tmp/tun2socks.zip" -d "$tmp/t2s"

curl -fsSL -o "$tmp/wintun.zip" https://www.wintun.net/builds/wintun-0.14.1.zip
echo "07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51  $tmp/wintun.zip" | sha256sum -c --quiet
unzip -q "$tmp/wintun.zip" -d "$tmp/wintun"

mkdir -p tun2socks
cp "$tmp/t2s/tun2socks-windows-amd64.exe" tun2socks/tun2socks.exe
cp "$tmp/wintun/wintun/bin/amd64/wintun.dll" tun2socks/wintun.dll
echo "tun2socks + wintun ok"
