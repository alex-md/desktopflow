import { app, BrowserWindow, ipcMain, shell } from "electron";
import path from "node:path";
import type { Flow, RecorderEvent } from "../shared/models";
import { abortNativeFlow, getNativeRecorderStatus, getPermissionSnapshot, listNativeWindows, runNativeFlow, startNativeRecording, stopNativeRecording } from "./nativeBridge";
import { buildWindowCatalog } from "./windowCatalog";
import { configureWorkspaceRoot, deleteFlow, getWorkspaceRoot, loadWorkspace, saveFlow, seedWorkspaceFrom } from "./workspace";

let mainWindow: BrowserWindow | null = null;

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
  ipcMain.handle("runner:run", async (_event, flow: Flow) =>
    runNativeFlow(getWorkspaceRoot(), flow.id)
  );
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
  void stopNativeRecording().catch(() => undefined);
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});
