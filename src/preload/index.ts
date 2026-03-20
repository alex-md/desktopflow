import { contextBridge, ipcRenderer } from "electron";
import type { Flow, FlowRunReport, FlowStep, PermissionSnapshot, RecorderEvent, RecorderStatus, TargetHint, WorkspacePayload } from "../shared/models";
const api = {
  loadWorkspace: () => ipcRenderer.invoke("workspace:load") as Promise<WorkspacePayload>,
  saveFlow: (flow: Flow) => ipcRenderer.invoke("workspace:save-flow", flow) as Promise<WorkspacePayload>,
  deleteFlow: (flowID: string) => ipcRenderer.invoke("workspace:delete-flow", flowID) as Promise<WorkspacePayload>,
  runFlow: (flow: Flow) => ipcRenderer.invoke("runner:run", flow) as Promise<FlowRunReport>,
  abortFlow: (flowID: string) => ipcRenderer.invoke("runner:abort", flowID) as Promise<boolean>,
  getPermissions: () => ipcRenderer.invoke("system:permissions") as Promise<PermissionSnapshot>,
  getRecorderStatus: () => ipcRenderer.invoke("recorder:status") as Promise<RecorderStatus>,
  startRecording: (targetHint: TargetHint) => ipcRenderer.invoke("recorder:start", targetHint) as Promise<boolean>,
  stopRecording: () => ipcRenderer.invoke("recorder:stop") as Promise<FlowStep[]>,
  onRecorderEvent: (listener: (event: RecorderEvent) => void) => {
    const wrapped = (_event: Electron.IpcRendererEvent, payload: RecorderEvent) => listener(payload);
    ipcRenderer.on("recorder:event", wrapped);
    return () => {
      ipcRenderer.removeListener("recorder:event", wrapped);
    };
  }
};

contextBridge.exposeInMainWorld("desktopflow", api);
