# Desktopflow

Desktopflow is a **free and open source** macOS desktop automation app for recording, editing, and replaying workflows from real desktop interactions.

It is designed to help you automate repetitive tasks without writing scripts, while keeping your flows and anchors stored locally in a simple, file-based workspace.

## Features

- Record desktop interactions into reusable flows
- Edit flows in a modern desktop UI
- Run flows directly inside the app
- Inspect available windows on the system
- Manage required macOS permissions
- Store flows and anchors as JSON in a local workspace
- Use a native Swift bridge for macOS-specific recording and playback capabilities

## Screenshots

_Add screenshots or GIFs of the recorder, editor, runner, and permissions screens here._

## How it works

Desktopflow uses an Electron app for the main interface, built with React and TypeScript.

A Swift sidecar handles macOS-specific capabilities such as:

- window discovery
- permissions
- recording
- playback

Flow data is stored in a workspace directory and follows a simple JSON-based structure:

```text
WorkspaceData/
  flows/
  anchors/

## Local App Install

For normal day-to-day use, install a packaged app instead of running `npm run dev`:

```bash
npm run install:local
```

To build, install, and open the app immediately:

```bash
npm run install:local:launch
```

This installs `Desktopflow.app` into `/Applications`, so you can launch it from Spotlight, Launchpad, Finder, or pin it to the Dock.
