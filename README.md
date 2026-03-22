# Desktopflow

Desktopflow is now an Electron application built with React and TypeScript. It keeps the existing `WorkspaceData/` JSON contract for flows and anchors, and ports the Swift shell into a desktop app that can be developed with standard web tooling.

## Current scope

- Electron main/preload process with a React renderer
- Swift `DesktopflowBridge` executable for native macOS window discovery, permissions, recording, and playback
- Workspace loader that reads and writes `WorkspaceData/flows/*.json` and `WorkspaceData/anchors/*.json`
- Overview, Recorder, Flow Editor, Runner, and Permissions screens
- Native recorder flow creation streamed back into the Electron UI
- Native playback for non-vision steps through the existing Swift platform code
- Existing sample workspace data loads without migration

## Build and run

```bash
npm install
npm run dev
```

For a production build:

```bash
npm run build
```

To produce a downloadable macOS app bundle and `.dmg`:

```bash
npm run dist:mac
```

That build:

- compiles the Electron app into `out/`
- compiles the native Swift bridge in release mode
- bundles the bridge and seed `WorkspaceData/` into `Desktopflow.app`
- emits a `.dmg` into `dist/`

To build the Intel release artifact that should appear on GitHub Releases:

```bash
npm run dist:mac:x64
```

That emits `dist/Desktopflow-<version>-x64.dmg`.

Packaged builds no longer write into the app bundle. On first launch, Desktopflow seeds a writable workspace under the current user's application data directory and runs from there.

If you want Gatekeeper-friendly distribution, provide Apple signing credentials before packaging:

```bash
export APPLE_ID="you@example.com"
export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export APPLE_TEAM_ID="TEAMID1234"
npm run dist:mac
```

Without those variables, the app still packages successfully, but electron-builder falls back to ad-hoc signing and skips notarization.

## GitHub releases

Tagging a release runs `.github/workflows/release.yml`, which builds the app on GitHub's Intel macOS runner and uploads the resulting `Desktopflow-<version>-x64.dmg` to the matching GitHub Release.

The workflow expects:

- a tag in the form `v<package.json version>` such as `v0.1.0`
- the repository `GITHUB_TOKEN` provided by GitHub Actions
- optional Apple signing secrets if you want a signed and notarized release build:
  - `APPLE_ID`
  - `APPLE_APP_SPECIFIC_PASSWORD`
  - `APPLE_TEAM_ID`

During development, the app resolves its workspace from `./WorkspaceData` by default. Packaged builds use a writable workspace under the current user's app data directory unless `DESKTOPFLOW_WORKSPACE_ROOT` is set.

## Port boundary

The original Swift package is still present in `Sources/` as legacy reference code, but the active application entrypoint is now the Electron stack in `src/`.

The Electron app now uses a Swift sidecar for the macOS-specific pieces that Electron alone cannot replace reliably. The remaining major gap is anchor-based screen matching and capture: the bridge still uses placeholder frame/matcher implementations, just like the earlier Swift shell.

## Workspace layout

```text
src/
  main/
  preload/
  renderer/
  shared/
WorkspaceData/
Sources/        # legacy Swift reference
docs/
```
