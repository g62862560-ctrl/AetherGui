# AetherGui Project Memory

## Release rule — mandatory

- **Always build and publish releases with `./release.sh X.Y.Z`.**
- On Windows, use `release.bat X.Y.Z`; it is only a wrapper around `release.sh`.
- Never manually bump versions, create tags, package assets, or call `gh release create` for a normal release.
- Never substitute `build.bat`, `flutter build`, or an ad-hoc GitHub workflow for the release script.
- Before running a release, the Git working tree must be clean and no process may lock `publish/AetherGui.exe` or `publish/aether.exe`.
- `release.sh` is authoritative: it validates the version, runs checks/tests, builds Windows and split Android release artifacts, generates APK/SBOM/checksum reports, commits, tags, pushes, and publishes the GitHub release.

## Development builds

- `build.bat` builds the Windows application only; it is not a release command.
- `flutter/build-debug.bat` builds an ARM64-only Android debug APK; it is not a release command.

## Android connection architecture

- The intended connection order is: Flutter starts the Aether core → waits for its local SOCKS listener → starts `AetherVpn` → Android establishes the TUN → hev-socks5-tunnel forwards TUN traffic to Aether's SOCKS listener.
- Do not establish the Android VPN before the local proxy is ready; another active/broken VPN can otherwise block Aether bootstrap.
- `AetherVpn` is authoritative for native VPN state. It publishes `starting`, `connected`, `stopping`, `disconnected`, and `error`, including ownership and a disconnect reason.
- Always check the Boolean results from native tun2socks start/stop calls. A failed native start must close the TUN, clear ownership, notify Flutter, and stop the service.

## VPN revocation and disconnect semantics

- When another VPN takes ownership: `onRevoke` stops tun2socks, closes the TUN, reports `reason=revoked`, stops the service, cancels Flutter's connection loop, terminates the Aether core, releases Psiphon's datastore, and offers **Reconnect Aether**.
- A user or notification disconnect must report `reason=requested`; it must never be presented as another-VPN takeover.
- `vpnActive()` means **Aether owns its TUN**, not merely that Android reports some VPN transport.

## Core process ownership

- Only one Aether core process may run at a time. Never overlap protocol/core starts, especially Psiphon starts; Psiphon's datastore is single-owner and concurrent workers can time out opening it.
- Stop gracefully with `SIGTERM`, wait, then use `SIGKILL` only after the timeout.
- Before killing a stale PID, verify `/proc/<pid>/cmdline` identifies `libaether`; never kill a process solely because its PID is in `core.pid`.
- Delete `core.pid` only when it still belongs to that Aether process, and remove invalid/stale PID metadata.

## Android ABI policy

- Local Android debug APKs are `arm64-v8a` only and are built with `flutter/build-debug.bat`.
- Official releases contain split APKs for `arm64-v8a`, `armeabi-v7a`, and `x86_64`, produced only by `release.sh`.
- Flutter's `--target-platform android-arm64` filters the Flutter engine but not manually bundled JNI libraries; preserve the debug-only Gradle exclusions for non-ARM64 helpers.

## Privacy and UI invariants

- Never display the exit IP address on the Home screen. The connected route row may show only the exit country flag; its accessibility label may contain the country name but not the IP.
- Core technical logs may remain visible in the activity log, but copied/saved diagnostic reports must pass through credential redaction and bounded retention.
- Never log, persist in diagnostics, or echo Core input values such as OTPs, access codes, passwords, or tokens.
- Keep visible state based on explicit connection/native state, not button color or process fields alone.

## Native dependency policy

- Aether is pinned to `v2.4.0`; hev-socks5-tunnel is pinned to `2.17.1`.
- Never replace versioned native downloads with `/latest/` URLs.
- When updating Aether, review upstream release notes and update the version plus all pinned SHA-256 checksums together. Aether, Lyrebird, and Psiphon must come from the same upstream archive/version.

## Release signing

- Official Android releases must use the existing Aether release key, never the debug key.
- Expected release certificate SHA-256: `94a974070556d47e18dfcb8a465fd8442a3e6a1750258a38856d4b306114f273`.
- `release.sh` must remain the single release path so signing, reports, checksums, tags, and assets stay consistent.

## Known limitations — do not overclaim

- There is no app-owned fail-closed kill switch. The UI only directs users to Android's Always-on VPN / Block connections without VPN settings.
- IPv4/IPv6/DNS/UDP leak prevention is not certified without real-device network testing.
- Tor and reverse routes remain TCP-only for applications that require UDP.
- Expert settings are app-private but not encrypted; debug/trace logs may contain sensitive upstream data.
- Unit/widget tests validate behavior and layout but do not prove live protocol/server availability.

## Knowledge graph

- Treat `graphify-out/graph.json` as the local architecture map when present.
- After meaningful code or documentation changes, run `graphify . --update` (use `--code-only` if no supported LLM API key is configured), then `graphify cluster-only .` to refresh the report and visualization.
- Do not commit `graphify-out/`; it is intentionally ignored.
