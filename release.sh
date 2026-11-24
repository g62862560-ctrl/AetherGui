#!/usr/bin/env bash
# Usage: ./release.sh 1.0.1
# Bumps the version of both apps, tests, builds the Windows zip and one Android APK per CPU, commits, tags vX.Y.Z,
# and publishes a GitHub release. Check for updates in both apps compares against that tag.
set -euo pipefail
cd "$(dirname "$0")"
v=${1:?usage: ./release.sh X.Y.Z}
gh=$(command -v gh || echo "/c/Program Files/GitHub CLI/gh.exe")
release_cert_sha256=94a974070556d47e18dfcb8a465fd8442a3e6a1750258a38856d4b306114f273
fail() { echo "error: $*" >&2; exit 1; }

[[ $v =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must look like 1.0.1"
grep -Fxq "## $v" flutter/assets/release_notes.txt || fail "add release notes for $v to flutter/assets/release_notes.txt"
git diff --quiet HEAD -- && [ -z "$(git ls-files --others --exclude-standard -- . ':!graphify-out')" ] || fail "commit your changes first"
git rev-parse -q --verify "refs/tags/v$v" >/dev/null && fail "tag v$v already exists"
current=$(sed -n 's|.*<Version>\([0-9.]*\)</Version>.*|\1|p' AetherGui.csproj)
[ "$v" != "$current" ] && [ "$(printf '%s\n' "$current" "$v" | sort -V | tail -1)" = "$v" ] || fail "$v is not newer than $current"
"$gh" auth status >/dev/null 2>&1 || fail "run: gh auth login"

sed -i "s|<Version>[0-9.]*</Version>|<Version>$v</Version>|" AetherGui.csproj
build=$(sed -n 's/^version: [^+]*+\([0-9]*\).*/\1/p' flutter/pubspec.yaml)
# Local signed test builds through 2028 exist; official updates must supersede them.
next_build=$((build + 1))
if (( next_build <= 2028 )); then next_build=2029; fi
sed -i "s/^version: [0-9.]*+[0-9]*/version: $v+$next_build/" flutter/pubspec.yaml # +N must grow
sed -i -E "s/(AetherGui-|v)[0-9]+\.[0-9]+\.[0-9]+([-<\/])/\1$v\2/g" docs/index.html # landing page version and download links

dotnet run --project tests/CoreChecks.csproj
./fetch_tun2socks.sh
dotnet publish AetherGui.csproj -c Release -o publish
(cd flutter && flutter pub get --enforce-lockfile && flutter analyze && flutter test && flutter build apk --release --split-per-abi)

# Only what the app needs: never identity files (*.toml hold private keys) or anything else left in publish/.
out=release-out; rm -rf "$out"; mkdir -p "$out/AetherGui"
cp -r publish/AetherGui.exe publish/aether.exe publish/pt publish/tun2socks publish/LICENSES "$out/AetherGui/"
(cd "$out" && python -I -m zipfile -c "AetherGui-$v-windows-x64.zip" AetherGui)
mkdir -p "$out/reports"
for f in flutter/build/app/outputs/flutter-apk/app-*-release.apk; do # one APK per CPU: arm64-v8a, armeabi-v7a, x86_64
  a=${f##*/app-}; apk="$out/AetherGui-$v-android-${a%-release.apk}.apk"; cp "$f" "$apk"
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File flutter/tool/report-apk.ps1 -ApkPath "$apk" -ExpectedCertificateSha256 "$release_cert_sha256" | tee -a "$out/reports/apk-report.txt"
done
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File flutter/tool/generate-sbom.ps1 -OutputPath "$out/reports/sbom.cdx.json"

git add AetherGui.csproj flutter/pubspec.yaml docs/index.html
git commit -m "Release v$v"
git tag "v$v"
git push origin HEAD "v$v"
(cd "$out" && sha256sum AetherGui-* reports/apk-report.txt reports/sbom.cdx.json > SHA256SUMS.txt)
# Keep verification reports and checksums locally; publish only installable downloads.
"$gh" release create "v$v" "$out/AetherGui-$v-windows-x64.zip" "$out"/AetherGui-$v-android-*.apk --title "v$v" --generate-notes
echo "Released v$v"
