/// <reference types="vite/client" />

import type { Flow, FlowRunReport, FlowStep, PermissionSnapshot, RecorderEvent, RecorderStatus, RunFlowRequestPayload, TargetHint, WorkspacePayload } from "../../shared/models";

declare global {
  interface Window {
    desktopflow: {
      loadWorkspace: () => Promise<WorkspacePayload>;
      saveFlow: (flow: Flow) => Promise<WorkspacePayload>;
      deleteFlow: (flowID: string) => Promise<WorkspacePayload>;
      runFlow: (request: RunFlowRequestPayload) => Promise<FlowRunReport>;
      abortFlow: (flowID: string) => Promise<boolean>;
      getPermissions: () => Promise<PermissionSnapshot>;
      getRecorderStatus: () => Promise<RecorderStatus>;
      startRecording: (targetHint: TargetHint) => Promise<boolean>;
      stopRecording: () => Promise<FlowStep[]>;
      onRecorderEvent: (listener: (event: RecorderEvent) => void) => () => void;
    };
  }
}

export {};
