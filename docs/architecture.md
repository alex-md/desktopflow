# Architecture Notes

## Canonical coordinate space

Desktopflow uses the target window's live content rect as the single source of truth for all normalized coordinates. The frame rect is still stored for diagnostics, but replay clicks, preview overlays, and anchor regions are mapped against the content rect only.

This decision avoids a common replay bug: recording against a captured game surface and replaying against a frame-including rect after the window moves.

## Spike boundaries

This implementation is the first milestone foundation:

- semantic flow model
- protocol-driven runner
- file-backed repositories in the current workspace
- SwiftUI shell that exposes the core concepts

It intentionally stops short of macOS platform integration. The next milestone should connect `WindowBinder`, `FrameProvider`, and `InputDispatcher` to real platform APIs without changing the core runner contract.
