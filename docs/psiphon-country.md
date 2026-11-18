# Psiphon country selection

Core settings > Psiphon offers Automatic plus 25 common country requests with real flag images (embedded PNGs), names and ISO codes. The choices are a subset of the official Windows client's region choices, not a promise of live availability. Windows does not render Unicode flag emoji, so the selector draws embedded flag images instead.

The persisted `PsiphonRegion` field in LocalAppData/AetherGui/core-options.json defaults to empty (Automatic) for old settings. Values are trimmed, uppercased and validated. Existing arguments, environment and timeout remain intact. Save validates before replacing the file.

The bundled `aether.exe --help` confirms `--psiphon-region <cc>` and `AETHER_PSIPHON_REGION`, and identifies `AvailableEgressRegions` as the live availability notice. The GUI adds one region flag only for --psiphon, --psiphon-only and --psiphon-reverse. Reverse mode selects the carrier country, not the final WARP exit. Automatic adds nothing. Existing advanced region flags (split or equals syntax) or environment settings take precedence without adding a competing flag. Custom Psiphon configurations are not rewritten.

The separate psiphon3.exe launcher remains unchanged apart from an explanatory log message. It uses its own country setting; select that in its own window. Official Windows source stores EgressRegion, but this integration deliberately does not overwrite that external application's preference or invent command-line flags.

## Sources inspected

- https://www.netify.ai/resources/vpns/psiphon — observed IP/PoP inventory (27 countries when fetched), not a selectable-server guarantee.
- https://psiphon.ca/en/index.html — fetch attempted twice; connection failed in this environment.
- https://raw.githubusercontent.com/Psiphon-Inc/psiphon-windows/master/src/webui/main.html — official region choice list; all 25 offered codes occur here.
- https://raw.githubusercontent.com/Psiphon-Inc/psiphon-windows/master/src/usersettings.cpp — separate Windows client's EgressRegion preference.
- https://raw.githubusercontent.com/Psiphon-Labs/psiphon-tunnel-core/master/psiphon/config.go — core configuration reference.
- Local aether.exe --help and pt/psiphon-tunnel-core.exe -help — inspected without starting a tunnel or reading identity TOMLs.

## Validation

Run `dotnet run --project D:\ProjectS\AetherGui\tests\CoreChecks.csproj -c Release`.
Country tests cover normalization, invalid choices, clean labels, unique codes, persistence, legacy defaults, Automatic, all preset scopes, advanced overrides and UI restoration. Existing CoreChecks also exercise settings layout and core behaviors without starting a tunnel/system proxy.

Standalone build: `dotnet publish -c Release -o D:\ProjectS\AetherGui\publish`. The project enables win-x64, SelfContained and PublishSingleFile. Actual remote server availability is not tested by CoreChecks.
