# Reconnection validation — 2026-11-21

## Confirmed defects fixed

- Flutter process shutdown swallowed the final exit timeout, and the UI discarded ownership before waiting. A replacement could overlap a core whose exit was unconfirmed. Retain ownership until confirmed exit and propagate failure.
- Flutter native teardown failure returned before stopping the owned core. Stop the core on that path, retain native ownership for reconciliation, and inspect actual VPN ownership even when session flags are absent.
- Windows discarded the core handle after an unchecked exit wait or cleanup exception. Keep the handle and block replacement until exit is confirmed.
- Windows connectivity checks now check cancellation before sending and before accepting a late success; request and response disposal is regression-tested.
- The earlier Flutter probe fix gives each request its own client and force-closes sockets on cancellation/timeout.

Lifecycle diagnostics report shutdown requests, core PID, confirmed exit, cleanup errors, and blocked replacement. No credentials or exit IPs are added by these diagnostics.

## Automated validation

- Flutter: 57 tests passed; analysis clean.
- Windows: CoreChecks passed; Release build passed with zero warnings/errors.
- Regression coverage includes real probe socket cancellation, subsequent successful probing, PID metadata cleanup after exit, repeated process cleanup, unconfirmed-exit failure, and cancellation winning over late HTTP success.
- Android debug build and release-signed local test build succeeded.

## Physical Android test

Device: MTN_NX1, Android 16. Local test build uses version code 2026 because installed version 1.0.24 had code 2025. Repository release numbering was not changed. Installing the patched APK was a normal update; app data was preserved. Installation itself replaces the app process; no process restart was used during the following recovery tests.

App PID remained 26940 throughout:

1. Connected via MASQUE HTTP/2 → Psiphon (successful live delay test).
2. Disabled mobile data for 18 seconds, restored it: recovered via WARP-in-WARP → Psiphon with successful connectivity.
3. Manual disconnect/reconnect: some routes failed, then WireGuard → Psiphon connected successfully.
4. Second 18-second mobile outage: recovered via WARP-in-WARP (gool), live delay 433 ms.

Initial network settings were Wi-Fi off, mobile data on. Those settings were restored. Tests do not prove absence of all native/helper leaks; no heap/FD profiling was performed.

## Remaining validation boundaries

- Windows live tunnel/outage and Wi-Fi/mobile handover were not exercised.
- Standalone MASQUE, HTTP/2 and Psiphon were not individually certified across repeated outages; tested routes are listed above.
- Native library source is not present in this checkout; Java/native completion acknowledgements are relied upon.
- This is not leak-prevention or kill-switch certification.
- Tor progress UI parses both `Bootstrapped N%` and `tor reaching the network: N%`. Android build 2028 was installed and its waiting-state progress bar was verified visible; numeric updates remain unverified live.
- After Tor UI additions: 58 Flutter tests passed, analysis clean, and Windows checks/build passed.
- Official release numbering now supersedes local Android test builds through code 2028.
