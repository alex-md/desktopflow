import { BrowserWindow, screen } from "electron";

const OVERLAY_WIDTH = 320;
const OVERLAY_HEIGHT = 108;
const OVERLAY_MARGIN = 24;
const OVERLAY_HIDE_DELAY_MS = 2600;

type PlaybackOverlayState = {
  isRunning: boolean;
  shortcutAvailable: boolean;
};

let overlayWindow: BrowserWindow | null = null;
let hideTimer: NodeJS.Timeout | null = null;

const escapeHtml = (value: string) =>
  value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;")
    .replaceAll("'", "&#39;");

const overlayBodyCopy = (shortcutAvailable: boolean) =>
  shortcutAvailable
    ? "Press cmd, shift, and tilde at the same time to kill playback."
    : "Press cmd, shift, and tilde at the same time to kill playback. If macOS blocks it, use Abort in Desktopflow.";

const buildOverlayHtml = ({ isRunning, shortcutAvailable }: PlaybackOverlayState) => {
  const heading = isRunning ? "Playback in progress" : "Playback not in progress";
  const badge = isRunning ? "LIVE" : "IDLE";
  const badgeClass = isRunning ? "running" : "idle";
  const body = overlayBodyCopy(shortcutAvailable);

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Playback Status</title>
    <style>
      :root {
        color-scheme: dark;
        font-family: "SF Pro Text", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }

      * {
        box-sizing: border-box;
      }

      html,
      body {
        margin: 0;
        width: 100%;
        height: 100%;
        background: transparent;
      }

      body {
        display: flex;
        align-items: stretch;
        justify-content: stretch;
        padding: 0;
        overflow: hidden;
      }

      .panel {
        width: 100%;
        height: 100%;
        display: flex;
        flex-direction: column;
        gap: 10px;
        padding: 14px 16px;
        border-radius: 18px;
        border: 1px solid rgba(255, 255, 255, 0.12);
        background:
          radial-gradient(circle at top left, rgba(61, 140, 255, 0.22), transparent 34%),
          linear-gradient(180deg, rgba(17, 20, 28, 0.94), rgba(9, 11, 16, 0.92));
        box-shadow:
          0 24px 48px rgba(0, 0, 0, 0.34),
          inset 0 1px 0 rgba(255, 255, 255, 0.08);
        backdrop-filter: blur(22px) saturate(155%);
        -webkit-backdrop-filter: blur(22px) saturate(155%);
        color: #f5f7fb;
      }

      .header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
      }

      .title {
        margin: 0;
        font-size: 14px;
        font-weight: 680;
        letter-spacing: -0.02em;
      }

      .badge {
        flex-shrink: 0;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-width: 52px;
        padding: 5px 8px;
        border-radius: 999px;
        border: 1px solid rgba(255, 255, 255, 0.14);
        font-size: 10px;
        font-weight: 800;
        letter-spacing: 0.12em;
      }

      .badge.running {
        background: rgba(52, 199, 89, 0.16);
        color: #95f7b0;
      }

      .badge.idle {
        background: rgba(160, 172, 194, 0.12);
        color: #d4d9e2;
      }

      .copy {
        margin: 0;
        color: rgba(229, 234, 242, 0.86);
        font-size: 12px;
        line-height: 1.45;
      }
    </style>
  </head>
  <body>
    <section class="panel" aria-live="polite">
      <div class="header">
        <h1 class="title">${escapeHtml(heading)}</h1>
        <span class="badge ${badgeClass}">${escapeHtml(badge)}</span>
      </div>
      <p class="copy">${escapeHtml(body)}</p>
    </section>
  </body>
</html>`;
};

const overlayDataUrl = (state: PlaybackOverlayState) => `data:text/html;charset=utf-8,${encodeURIComponent(buildOverlayHtml(state))}`;

const clearHideTimer = () => {
  if (hideTimer) {
    clearTimeout(hideTimer);
    hideTimer = null;
  }
};

const placeOverlayWindow = (window: BrowserWindow) => {
  const { workArea } = screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
  window.setBounds({
    width: OVERLAY_WIDTH,
    height: OVERLAY_HEIGHT,
    x: Math.round(workArea.x + workArea.width - OVERLAY_WIDTH - OVERLAY_MARGIN),
    y: Math.round(workArea.y + workArea.height - OVERLAY_HEIGHT - OVERLAY_MARGIN)
  });
};

const ensureOverlayWindow = async () => {
  if (overlayWindow && !overlayWindow.isDestroyed()) {
    placeOverlayWindow(overlayWindow);
    return overlayWindow;
  }

  overlayWindow = new BrowserWindow({
    width: OVERLAY_WIDTH,
    height: OVERLAY_HEIGHT,
    x: 0,
    y: 0,
    show: false,
    frame: false,
    transparent: true,
    resizable: false,
    movable: false,
    minimizable: false,
    maximizable: false,
    closable: false,
    focusable: false,
    skipTaskbar: true,
    fullscreenable: false,
    roundedCorners: true,
    backgroundColor: "#00000000",
    hasShadow: true,
    visualEffectState: "active",
    webPreferences: {
      devTools: false
    }
  });

  overlayWindow.setAlwaysOnTop(true, "screen-saver");
  overlayWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  overlayWindow.setIgnoreMouseEvents(true, { forward: true });
  overlayWindow.setMenuBarVisibility(false);
  overlayWindow.on("closed", () => {
    overlayWindow = null;
  });

  placeOverlayWindow(overlayWindow);
  return overlayWindow;
};

const renderOverlay = async (state: PlaybackOverlayState) => {
  clearHideTimer();
  const window = await ensureOverlayWindow();
  await window.loadURL(overlayDataUrl(state));
  if (!window.isVisible()) {
    window.showInactive();
  }
};

export const showRunningPlaybackOverlay = async (shortcutAvailable: boolean) => {
  await renderOverlay({
    isRunning: true,
    shortcutAvailable
  });
};

export const showStoppedPlaybackOverlay = async (shortcutAvailable: boolean) => {
  await renderOverlay({
    isRunning: false,
    shortcutAvailable
  });

  hideTimer = setTimeout(() => {
    overlayWindow?.hide();
    hideTimer = null;
  }, OVERLAY_HIDE_DELAY_MS);
};

export const destroyPlaybackOverlay = () => {
  clearHideTimer();
  if (overlayWindow && !overlayWindow.isDestroyed()) {
    overlayWindow.destroy();
  }
  overlayWindow = null;
};
