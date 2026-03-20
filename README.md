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

The app resolves its workspace from `./WorkspaceData` by default. Override that with `DESKTOPFLOW_WORKSPACE_ROOT` if you want to point the Electron app at a different project root.

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
