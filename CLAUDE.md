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

## Knowledge graph

- Treat `graphify-out/graph.json` as the local architecture map when present.
- After meaningful code or documentation changes, run `graphify . --update` (use `--code-only` if no supported LLM API key is configured), then `graphify cluster-only .` to refresh the report and visualization.
- Do not commit `graphify-out/`; it is intentionally ignored.
