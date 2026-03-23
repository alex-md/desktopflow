import { app, BrowserWindow, globalShortcut, ipcMain, shell } from "electron";
import path from "node:path";
import type { Flow, RecorderEvent } from "../shared/models";
import { abortNativeFlow, getNativeRecorderStatus, getPermissionSnapshot, listNativeWindows, runNativeFlow, startNativeRecording, stopNativeRecording } from "./nativeBridge";
import { destroyPlaybackOverlay, showRunningPlaybackOverlay, showStoppedPlaybackOverlay } from "./playbackOverlay";
import { buildWindowCatalog } from "./windowCatalog";
import { configureWorkspaceRoot, deleteFlow, getWorkspaceRoot, loadWorkspace, saveFlow, seedWorkspaceFrom } from "./workspace";

let mainWindow: BrowserWindow | null = null;
const PLAYBACK_KILL_ACCELERATOR = "CommandOrControl+Alt+Escape";

globalThis.__desktopflowRecorderBroadcast = (event: RecorderEvent) => {
  mainWindow?.webContents.send("recorder:event", event);
};

const loadWorkspaceWithWindows = async () => {
  const workspace = await loadWorkspace();

  try {
    return {
      ...workspace,
      windows: await listNativeWindows()
    };
  } catch {
    return {
      ...workspace,
      windows: buildWindowCatalog(workspace.flows)
    };
  }
};

const resolvePackagedWorkspaceRoot = () => path.join(app.getPath("userData"), "WorkspaceData");
const resolveBundledWorkspaceSeedRoot = () => path.join(process.resourcesPath, "WorkspaceData");

const unregisterPlaybackKillShortcut = () => {
  globalShortcut.unregister(PLAYBACK_KILL_ACCELERATOR);
};

const registerPlaybackKillShortcut = (flowID: string) => {
  unregisterPlaybackKillShortcut();
  return globalShortcut.register(PLAYBACK_KILL_ACCELERATOR, () => {
    void abortNativeFlow(flowID);
  });
};

const runFlowWithPlaybackOverlay = async (flow: Flow) => {
  const shortcutAvailable = registerPlaybackKillShortcut(flow.id);
  await showRunningPlaybackOverlay(shortcutAvailable);

  try {
    return await runNativeFlow(getWorkspaceRoot(), flow);
  } finally {
    unregisterPlaybackKillShortcut();
    await showStoppedPlaybackOverlay(shortcutAvailable);
  }
};

const initializeWorkspace = async () => {
  if (process.env.DESKTOPFLOW_WORKSPACE_ROOT) {
    configureWorkspaceRoot(process.env.DESKTOPFLOW_WORKSPACE_ROOT);
    return;
  }

  if (!app.isPackaged) {
    configureWorkspaceRoot(process.cwd());
    return;
  }

  configureWorkspaceRoot(resolvePackagedWorkspaceRoot());
  await seedWorkspaceFrom(resolveBundledWorkspaceSeedRoot());
};

const createWindow = async () => {
  mainWindow = new BrowserWindow({
    width: 1480,
    height: 960,
    minWidth: 1220,
    minHeight: 840,
    backgroundColor: "#00000000",
    vibrancy: "sidebar",
    visualEffectState: "active",
    titleBarStyle: "hiddenInset",
    webPreferences: {
      preload: path.join(__dirname, "../preload/index.js")
    }
  });

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    void shell.openExternal(url);
    return { action: "deny" };
  });

  if (process.env.ELECTRON_RENDERER_URL) {
    await mainWindow.loadURL(process.env.ELECTRON_RENDERER_URL);
  } else {
    await mainWindow.loadFile(path.join(__dirname, "../renderer/index.html"));
  }

  mainWindow.on("closed", () => {
    mainWindow = null;
    unregisterPlaybackKillShortcut();
    destroyPlaybackOverlay();
    void stopNativeRecording().catch(() => undefined);
  });
};

app.whenReady().then(async () => {
  await initializeWorkspace();

  ipcMain.handle("workspace:load", async () => loadWorkspaceWithWindows());
  ipcMain.handle("workspace:save-flow", async (_event, flow: Flow) => {
    await saveFlow(flow);
    return loadWorkspaceWithWindows();
  });
  ipcMain.handle("workspace:delete-flow", async (_event, flowID: string) => {
    await deleteFlow(flowID);
    return loadWorkspaceWithWindows();
  });
  ipcMain.handle("runner:run", async (_event, flow: Flow) => runFlowWithPlaybackOverlay(flow));
  ipcMain.handle("runner:abort", async (_event, flowID: string) => abortNativeFlow(flowID));
  ipcMain.handle("system:permissions", async () => getPermissionSnapshot());
  ipcMain.handle("recorder:status", async () => getNativeRecorderStatus());
  ipcMain.handle("recorder:start", async (_event, targetHint) => {
    await startNativeRecording(targetHint);
    return true;
  });
  ipcMain.handle("recorder:stop", async () => stopNativeRecording());

  await createWindow();

  app.on("activate", async () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      await createWindow();
    }
  });
});

app.on("before-quit", () => {
  unregisterPlaybackKillShortcut();
  destroyPlaybackOverlay();
  void stopNativeRecording().catch(() => undefined);
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});
