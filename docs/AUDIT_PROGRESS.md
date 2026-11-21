# AetherGui production audit and optimization progress

Date: 2026-11-21

This document tracks the comprehensive audit requested in `prompt1.docx`. It distinguishes verified work from recommendations and device-only validation. It is not a claim that VPN leak prevention or live protocol availability has been certified.

## Executive summary

The repository contains a Windows .NET 8 WinForms client and an Android Flutter client with a Kotlin `VpnService`, native Aether core, Lyrebird, Psiphon, hev-socks5-tunnel, and platform-specific packaging. Static analysis and existing automated tests pass, but the audit identified lifecycle and release-safety defects that take priority over speculative performance tuning.

The first implementation batch fixes two confirmed P0 problems:

1. Android no longer treats service dispatch as proof that the VPN owns a TUN. `vpnStart` completes only after the native service publishes `connected` with `owned=true`; a failure stops the core instead of presenting an unprotected session as VPN-connected.
2. The Windows watchdog no longer kills every process named `aether`. It receives the exact child PID and verifies the executable path before termination.

Release engineering is also hardened: release builds fail if the release keystore is absent, final APKs must match the expected certificate SHA-256, the duplicate hosted publisher is removed, and Windows PR CI is added.

## Architecture and connection lifecycle

### Windows

1. `Form1` serializes the UI connection session with `_cts` and `_attemptCts`.
2. `Aether.Start` launches the core with explicit arguments and loopback listeners.
3. `Aether.WaitConnectedAsync` distinguishes process start, SOCKS readiness, and a successful proxied HTTP request.
4. `MixedProxy` multiplexes HTTP and SOCKS5 on the stable local port.
5. Optional WinINet proxy and TUN mode are enabled after the core is usable.
6. Cleanup stops TUN routes before killing the core and disables the owned system proxy.

### Android

1. Flutter starts one Aether core process.
2. Flutter waits for the local SOCKS listener.
3. Flutter asks Kotlin to establish `AetherVpn`.
4. `AetherVpn` creates the TUN and starts hev-socks5-tunnel.
5. Kotlin acknowledges success only after `owned=true`.
6. Flutter tests proxied internet connectivity and shows connected state.
7. Revocation cancels the session, stops the core, and offers reconnect.

## Prioritized confirmed findings

### P0 — implemented and verified locally

- **Android false VPN success** — `MainActivity.kt`, `AetherVpn.kt`, `aether.dart`, `main.dart`. Service dispatch previously returned success before TUN/tun2socks establishment. Fixed with authoritative native acknowledgement and fail-closed Flutter behavior.
- **Windows broad process kill** — `Program.cs`, `Form1.cs`. Watchdog previously killed all processes named `aether`. Fixed by exact PID plus canonical executable-path verification.
- **Duplicate release implementation** — `.github/workflows/release.yml`. Hosted workflow duplicated versioning/tagging/publication and diverged from `release.sh`. Replaced with a policy guard that cannot publish.
- **Fail-open Android release signing** — `build.gradle.kts`, `release.sh`, `report-apk.ps1`. Release builds previously could use the debug key and certificate reporting was optional. Release signing now requires `key.properties`, and official packaging enforces the expected certificate SHA-256.

### P1 — confirmed, recommended next

- `SystemProxy.cs` overwrites ProxyServer/ProxyOverride rather than transactionally snapshotting and restoring the exact previous values. A persisted ownership snapshot is needed for crash recovery and to avoid clobbering user changes.
- `TunMode.cs` cleanup can remove routes not created by the current session and uses unbounded synchronous PowerShell waits. Persist an owned-route journal and use bounded asynchronous process execution.
- `Aether.InstallCoreAsync` should require a checksum/signature and extract into a staging directory with path validation and atomic replacement.
- Android ownership is still process-static rather than generation-bound; add a start generation/token and a replayable native state snapshot for activity recreation.
- Android JNI start/stop and config I/O run on the service main thread. Move them to a single serialized worker after instrumentation coverage exists.
- Windows and Android need a dedicated singleton process manager so stale callbacks cannot affect a newer connection generation.

### P2 — maintainability and resource efficiency

- Track and await core output pumps and mixed-proxy client tasks rather than using unobserved fire-and-forget tasks.
- Reduce Android five-second continuous connectivity probing or make it network-event-aware after measuring reconnect behavior.
- Replace synchronous settings writes on Flutter UI paths with debounced atomic writes.
- Restore external Psiphon registry settings transactionally.
- Centralize native/Dart VPN state constants and include a payload schema version.

### P3 — optional

- Pin GitHub Actions by commit SHA and pin Flutter/JDK/.NET SDK versions for stronger reproducibility.
- Expand the SBOM to include native binaries, Gradle/Maven, Flutter engine, and toolchain identity.
- Add provenance/attestation for release artifacts.

## Tests and validation

### Implemented and verified

- Windows CoreChecks and production Release build: passed.
- Flutter static analysis: no issues; all 54 unit/widget tests passed.
- Watchdog executable-identity regression checks.
- Android debug Kotlin/Gradle compilation: BUILD SUCCESSFUL.
- Release signing configuration fails closed by construction; the official release script verifies the expected certificate.

### Implemented but not device-tested

- Android native VPN-start acknowledgement.
- VPN fail-closed behavior when native ownership is not confirmed.
- Revocation/start race behavior beyond unit/widget coverage.

### Blocked by environment

The following require physical Android devices or isolated Windows VMs and cannot be honestly certified by local unit tests:

- IPv4/IPv6/DNS/UDP leak behavior.
- Public-IP transition only after TUN ownership.
- Android Doze, screen-off, OEM battery management, Wi-Fi/mobile switching, and another-VPN takeover.
- Windows route/DNS behavior, crash recovery, and exact system-proxy restoration under administrator rights.
- Sustained throughput, CPU, RAM, battery, socket-handle, and reconnect stress measurements.
- Live Tor/Psiphon/MASQUE availability, which depends on external services and network censorship conditions.

## Measurement policy

No before/after speed, throughput, CPU, RAM, or battery improvement is claimed without a repeatable benchmark. Current changes address correctness and release integrity. Future performance work should record device/OS/network, protocol, cold/warm state, sample count, median, p95, and failure rate.

## Exact files changed in the first batch

- `Program.cs`
- `ProcessOwnership.cs`
- `Form1.cs`
- `tests/Program.cs`
- `flutter/android/app/src/main/kotlin/com/aether/aether_gui/MainActivity.kt`
- `flutter/android/app/build.gradle.kts`
- `flutter/lib/aether.dart`
- `flutter/lib/main.dart`
- `flutter/tool/report-apk.ps1`
- `release.sh`
- `.github/workflows/release.yml`
- `.github/workflows/windows-ci.yml`
- `.gitignore`
- `docs/AUDIT_PROGRESS.md`

## Exact next steps

1. Implement transactional WinINet proxy snapshot/restore with ownership and crash-safe persistence.
2. Implement a persisted TUN route journal and bounded cancellable command runner.
3. Harden core updates with mandatory verification, safe extraction, staging, and atomic replacement.
4. Add Android instrumentation seams/tests for TUN and native result injection.
5. Add connection-generation tokens and replayable VPN state.
6. Build a repeatable benchmark harness, then optimize only measured bottlenecks.

