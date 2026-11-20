# Aether VPN (Android)

Flutter Android client for [Aether](https://github.com/CluvexStudio/Aether): connects through aether and routes the whole device through it as a VPN.

Build: run `fetch_aether.sh` (downloads the pinned Aether release and builds hev-socks5-tunnel with the NDK), then `build-debug.bat` for the existing arm64-only debug APK. `build-release-arm64.bat` is the checked ARM64 release convenience: it restores the lockfile, analyzes, tests, builds, and reports the APK's ABI, SHA-256 and signing certificate when Android `apksigner` is available. The release workflow continues to produce split arm64-v8a, armeabi-v7a and x86_64 APKs.

`fetch_aether.sh` is reproducible: Aether is pinned to **v2.4.0**, each Android archive is checked against a checksum committed in the script, and hev-socks5-tunnel is pinned to **2.17.1**. Do not replace the version with a `latest` URL; update the version and all checksums together after reviewing upstream notes. It also emits native dependency metadata beside the fetched libraries.

## Verification and dependency inventory

Run `flutter pub get --enforce-lockfile`, `flutter analyze`, and `flutter test` before building. `tool/report-apk.ps1 -ApkPath <apk>` reports the packaged ABIs and SHA-256, then verifies and prints signer certificates when `apksigner` is installed under `ANDROID_HOME` or `ANDROID_SDK_ROOT`. `tool/generate-sbom.ps1` produces a CycloneDX 1.5 JSON inventory from the checked-in Pub lockfile and pinned native versions without adding another dependency. CI uploads both reports; release artifacts include them.

The committed `pubspec.lock` is the authoritative Dart dependency/version and hosted-package checksum record. Flutter's generated `NOTICES.Z` in the APK is the runtime license/About metadata provided by the existing toolchain. Native license notices remain upstream inside the pinned Aether archives; they should be reviewed whenever the pin changes.

## Core v2.4.0 update

The Android binaries come from the official v2.4.0 release for arm64-v8a,
armeabi-v7a and x86_64. Aether, Lyrebird and Psiphon are updated together;
the hev-socks5-tunnel pin is unchanged.

In v2.3, `--gool` means WireGuard inside MASQUE. Existing WARP-in-WARP
presets now use `--gool-classic`, preserving their saved indexes and behavior.
New WireGuard-in-MASQUE and WireGuard-in-MASQUE HTTP/2 presets are appended
and are also eligible for Auto. Additional TLS/ECH and Psiphon options remain
accessible through Core settings; consult the bundled core's help for syntax.

## Core feature access

The protocol menu includes MASQUE HTTP/3 and HTTP/2, HTTP/2 fragmentation,
WireGuard, nested WireGuard/MASQUE, standalone Tor/Psiphon, WARP through
Tor/Psiphon, and Tor/Psiphon through WARP. Forward modes route the Android VPN
and HTTP latency check through the secondary exit, not the base WARP listener.
Existing saved protocol indexes are preserved. Fresh Auto includes the fast H2
fallbacks plus MASQUE HTTP/2, WireGuard, WARP-in-WARP and MASQUE-in-MASQUE through
Psiphon. Tor and the other Psiphon routes remain manual because bootstrap can take
minutes. Set Auto try seconds high enough for Psiphon when needed.

Open **Core settings** while disconnected to configure additional arguments as a
JSON string array and `AETHER_*` / `RUST_LOG` environment variables as a JSON
object. This exposes scanning, obfuscation, DNS, endpoints, routing, upstream
proxies, TLS/ECH, Zero Trust, bridges, Psiphon region/fronting, diagnostics and
resource tuning supported by the bundled binary. The page displays that binary's
own `--help`; upstream documentation can describe a different version.

Example arguments (select MASQUE HTTP/2 first):

```json
["--fragment", "--scan", "balanced", "--noize", "gfw", "--stats"]
```

Arguments are passed without a shell, preserving spaces in bridge lines and
paths. App-owned protocol flags, listeners and helper paths cannot be overridden.
CLI flags take precedence over environment settings. Advanced startup timeout
applies when custom arguments/environment are nonempty. **Core input** sends a
response to the current process, including an emailed Zero Trust code, without
logging the response. Input is discarded if the process changed in the meantime.

### Limits (not a claim of complete feature parity)

- Expert options are not individually validated against the bundled core. Choose
  compatible settings; failures appear on the home screen and in the activity log.
- Settings are in app-private JSON, not encrypted storage. Core logs can expose
  sensitive data, especially at debug/trace level.
- File-based options require existing app-accessible files; there is no file
  import/export UI or standalone registration workflow yet.
- `SO_MARK` needs root/capabilities. Extra pluggable transport binaries must be
  packaged for Android. Fetch the core binaries before building a fresh checkout.
- The Android VPN frontend remains IPv4-only; core IPv6 endpoint selection is
  separate. This change does not add IPv6 VPN transport or verify leak prevention.
- Tor/reverse modes are TCP-only; they do not make UDP-only apps work through Tor.
- Selecting direct routes intentionally bypasses the tunnel. Organization Gateway
  can apply organization logging/filtering.
- Live end-to-end protocol coverage requires an Android device and reachable
  networks/accounts. Unit/widget tests only verify settings, argument generation
  and responsive layout, not that every protocol successfully connects.

Run checks with `flutter analyze` and `flutter test`.

## Credits

- [CluvexStudio](https://github.com/CluvexStudio): creators of [Aether](https://github.com/CluvexStudio/Aether), the engine this app runs.
- [heiher/hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel) (MIT): tun2socks used for the VPN.
