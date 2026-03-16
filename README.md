# Desktopflow

Desktopflow is a macOS-first automation recorder scaffold for Java-rendered game windows. This repository starts from the v1 blueprint and implements the protocol boundaries, semantic flow model, normalized coordinate contract, file-backed repositories, sample data, and a minimal SwiftUI shell.

## Current scope

- Swift package with separate `Core`, `Platform`, `Storage`, and `App` targets
- Canonical coordinate space locked to the live window content rect
- Semantic flow steps for attach, focus, wait, wait-for-anchor, click, key press, and checkpoint screenshot
- Recorder tab with live window selection, global/local input capture, and flow saving
- Protocol-driven runner with retry/timeouts and structured diagnostics hooks
- File-backed JSON repositories stored under `WorkspaceData/` in the current workspace
- Executable verification checks for coordinate mapping, flow serialization, and anchor-driven runner behavior

## Build and test

```bash
swift run DesktopflowApp
swift run DesktopflowChecks
```

The recorder uses macOS event monitors. Mouse clicks inside the selected window should appear immediately in the Recorder tab. Global key capture typically requires Input Monitoring permission, and key events are only recorded while the selected app is frontmost.

## Workspace layout

```text
Package.swift
Sources/
  DesktopflowApp/
  DesktopflowCore/
  DesktopflowPlatform/
  DesktopflowStorage/
Tests/
WorkspaceData/
```

## Immediate next steps

1. Replace the platform stubs with ScreenCaptureKit preview/capture and CoreGraphics input dispatch.
2. Add a real recorder pipeline that converts global low-level events into semantic steps.
3. Move flow and anchor persistence from JSON files to the SQLite schema described in the blueprint.
4. Extend the runner with pause/step/retry/skip UI controls and per-step overlays.
