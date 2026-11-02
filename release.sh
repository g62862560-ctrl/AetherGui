#!/usr/bin/env bash
# Usage: ./release.sh 1.0.1
# Bumps the version of both apps, tests, builds the Windows zip and one Android APK per CPU, commits, tags vX.Y.Z,
# and publishes a GitHub release. Check for updates in both apps compares against that tag.
set -euo pipefail
cd "$(dirname "$0")"
v=${1:?usage: ./release.sh X.Y.Z}
gh=$(command -v gh || echo "/c/Program Files/GitHub CLI/gh.exe")
fail() { echo "error: $*" >&2; exit 1; }

[[ $v =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must look like 1.0.1"
git diff --quiet HEAD -- && [ -z "$(git ls-files --others --exclude-standard -- . ':!graphify-out')" ] || fail "commit your changes first"
git rev-parse -q --verify "refs/tags/v$v" >/dev/null && fail "tag v$v already exists"
current=$(sed -n 's|.*<Version>\([0-9.]*\)</Version>.*|\1|p' AetherGui.csproj)
[ "$v" != "$current" ] && [ "$(printf '%s\n' "$current" "$v" | sort -V | tail -1)" = "$v" ] || fail "$v is not newer than $current"
"$gh" auth status >/dev/null 2>&1 || fail "run: gh auth login"

sed -i "s|<Version>[0-9.]*</Version>|<Version>$v</Version>|" AetherGui.csproj
build=$(sed -n 's/^version: [^+]*+\([0-9]*\).*/\1/p' flutter/pubspec.yaml)
sed -i "s/^version: [0-9.]*+[0-9]*/version: $v+$((build + 1))/" flutter/pubspec.yaml # +N is Android's versionCode, must grow
sed -i -E "s/(AetherGui-|v)[0-9]+\.[0-9]+\.[0-9]+([-<\/])/\1$v\2/g" docs/index.html # landing page version and download links

dotnet run --project tests/CoreChecks.csproj
dotnet publish AetherGui.csproj -c Release -o publish
(cd flutter && flutter test && flutter build apk --release --split-per-abi)

# Only what the app needs: never identity files (*.toml hold private keys) or anything else left in publish/.
out=release-out; rm -rf "$out"; mkdir -p "$out/AetherGui"
cp -r publish/AetherGui.exe publish/aether.exe publish/pt publish/LICENSES "$out/AetherGui/"
(cd "$out" && python -I -m zipfile -c "AetherGui-$v-windows-x64.zip" AetherGui)
for f in flutter/build/app/outputs/flutter-apk/app-*-release.apk; do # one APK per CPU: arm64-v8a, armeabi-v7a, x86_64
  a=${f##*/app-}; cp "$f" "$out/AetherGui-$v-android-${a%-release.apk}.apk"
done

git add AetherGui.csproj flutter/pubspec.yaml docs/index.html
git commit -m "Release v$v"
git tag "v$v"
git push origin HEAD "v$v"
"$gh" release create "v$v" "$out/AetherGui-$v-windows-x64.zip" "$out"/AetherGui-$v-android-*.apk --title "v$v" --generate-notes
echo "Released v$v"
