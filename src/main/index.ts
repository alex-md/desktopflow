import { app, BrowserWindow, globalShortcut, ipcMain, nativeImage, shell } from "electron";
import { existsSync } from "node:fs";
import path from "node:path";
import type { Flow, FlowRunOptions, FlowRunReport, RecorderEvent, RunFlowRequestPayload, RunStepResult } from "../shared/models";
import { abortNativeFlow, getNativeRecorderStatus, getPermissionSnapshot, listNativeWindows, runNativeFlow, startNativeRecording, stopNativeRecording } from "./nativeBridge";
import { destroyPlaybackOverlay, showRunningPlaybackOverlay, showStoppedPlaybackOverlay } from "./playbackOverlay";
import { buildWindowCatalog } from "./windowCatalog";
import { configureWorkspaceRoot, deleteFlow, getWorkspaceRoot, loadWorkspace, saveFlow, seedWorkspaceFrom } from "./workspace";

let mainWindow: BrowserWindow | null = null;
const PLAYBACK_KILL_ACCELERATOR = "CommandOrControl+Shift+`";
const PRODUCT_NAME = "Desktopflow";
const APP_ID = "com.desktopflow.app";

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
const resolveProjectRoot = () => path.resolve(__dirname, "../..");
const resolveDevIconPath = () => path.join(resolveProjectRoot(), "build", "icon.png");

const configureAppShell = () => {
  app.setName(PRODUCT_NAME);

  if (process.platform === "win32") {
    app.setAppUserModelId(APP_ID);
  }

  if (process.platform !== "darwin") {
    return;
  }

  const { dock } = app;
  if (!dock) {
    return;
  }

  dock.show();

  const devIconPath = resolveDevIconPath();
  if (!app.isPackaged && existsSync(devIconPath)) {
    dock.setIcon(nativeImage.createFromPath(devIconPath));
  }
};

const unregisterPlaybackKillShortcut = () => {
  globalShortcut.unregister(PLAYBACK_KILL_ACCELERATOR);
};

const registerPlaybackKillShortcut = (flowID: string) => {
  unregisterPlaybackKillShortcut();
  return globalShortcut.register(PLAYBACK_KILL_ACCELERATOR, () => {
    void abortNativeFlow(flowID);
  });
};

const prefixLoopReason = (report: FlowRunReport, iteration: number) => {
  if (!report.stopReason) {
    return iteration > 1 ? `Stopped during loop ${iteration}.` : report.stopReason;
  }

  if (report.status === "aborted") {
    return `Playback aborted during loop ${iteration}.`;
  }

  return iteration > 1 ? `Loop ${iteration}: ${report.stopReason}` : report.stopReason;
};

const withIteration = (stepResults: RunStepResult[], iteration: number) =>
  stepResults.map((result) => ({
    ...result,
    iteration
  }));

const runFlowWithPlaybackOverlay = async (flow: Flow, options: FlowRunOptions): Promise<FlowRunReport> => {
  const shortcutAvailable = registerPlaybackKillShortcut(flow.id);
  await showRunningPlaybackOverlay(shortcutAvailable);
  const startedAt = new Date().toISOString();
  const requestedLoops = Math.max(0, Math.trunc(options.loopCount));
  const stepResults: RunStepResult[] = [];
  let completedLoops = 0;

  try {
    while (requestedLoops === 0 || completedLoops < requestedLoops) {
      const iteration = completedLoops + 1;
      const report = await runNativeFlow(getWorkspaceRoot(), flow);
      stepResults.push(...withIteration(report.stepResults, iteration));

      if (report.status !== "succeeded") {
        return {
          flowID: flow.id,
          startedAt,
          finishedAt: new Date().toISOString(),
          status: report.status,
          stopReason: prefixLoopReason(report, iteration),
          stepResults,
          requestedLoops,
          completedLoops
        };
      }

      completedLoops += 1;
    }

    return {
      flowID: flow.id,
      startedAt,
      finishedAt: new Date().toISOString(),
      status: "succeeded",
      stepResults,
      requestedLoops,
      completedLoops
    };
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
    title: PRODUCT_NAME,
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
  configureAppShell();
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
  ipcMain.handle("runner:run", async (_event, request: RunFlowRequestPayload) => runFlowWithPlaybackOverlay(request.flow, request.options));
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
