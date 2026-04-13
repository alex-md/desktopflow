export const stepTypes = [
  "attachWindow",
  "focusWindow",
  "wait",
  "waitForAnchor",
  "clickAt",
  "scrollAt",
  "dragTo",
  "pressKey",
  "checkpointScreenshot"
] as const;

export const mouseButtons = ["left", "right", "center"] as const;
export const matchModes = ["pixelTemplate", "grayscaleTemplate"] as const;
export const runStatuses = ["pending", "running", "succeeded", "failed", "skipped", "aborted"] as const;

export type StepType = (typeof stepTypes)[number];
export type MouseButton = (typeof mouseButtons)[number];
export type MatchMode = (typeof matchModes)[number];
export type RunStatus = (typeof runStatuses)[number];

export interface NormalizedPoint {
  x: number;
  y: number;
}

export interface NormalizedRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface RetryPolicy {
  maxAttempts: number;
  backoffMs: number;
}

export interface TargetHint {
  bundleID?: string;
  appName?: string;
  windowTitleContains?: string;
  ownerPID?: number;
}

export interface StepCondition {
  anchorID: string;
  expectedVisible: boolean;
}

export interface StepParameters {
  point?: NormalizedPoint;
  endPoint?: NormalizedPoint;
  button?: MouseButton;
  anchorID?: string;
  pollIntervalMs?: number;
  durationMs?: number;
  deltaX?: number;
  deltaY?: number;
  keyCode?: string;
  modifiers: string[];
  label?: string;
}

export interface FlowStep {
  id: string;
  ordinal: number;
  type: StepType;
  params: StepParameters;
  enabled: boolean;
  timeoutMs?: number;
  retryPolicy?: RetryPolicy;
  preconditions: StepCondition[];
  postconditions: StepCondition[];
  debugNote?: string;
}

export interface Flow {
  id: string;
  name: string;
  description: string;
  targetHint: TargetHint;
  defaultTimeoutMs: number;
  createdAt: string;
  updatedAt: string;
  version: number;
  steps: FlowStep[];
}

export interface FlowRunOptions {
  loopCount: number;
}

export interface RunFlowRequestPayload {
  flow: Flow;
  options: FlowRunOptions;
}

export interface Anchor {
  id: string;
  assetID: string;
  name: string;
  region: NormalizedRect;
  threshold: number;
  matchMode: MatchMode;
  notes: string;
}

export interface WindowDescriptor {
  id: string;
  bundleID?: string;
  appName: string;
  title: string;
  ownerPID?: number;
}

export interface RunStepResult {
  stepID: string;
  startedAt: string;
  finishedAt: string;
  status: RunStatus;
  reason?: string;
  attempts: number;
  iteration?: number;
}

export interface FlowRunReport {
  flowID: string;
  startedAt: string;
  finishedAt: string;
  status: RunStatus;
  stopReason?: string;
  stepResults: RunStepResult[];
  requestedLoops?: number;
  completedLoops?: number;
}

export interface PermissionSnapshot {
  accessibility: boolean;
  inputMonitoring: boolean;
  screenRecording: boolean;
}

export interface RecorderEvent {
  type: "ready" | "stepCaptured" | "stopped" | "error";
  message?: string;
  count?: number;
  step?: FlowStep;
  steps?: FlowStep[];
}

export interface RecorderStatus {
  active: boolean;
  ready: boolean;
  startedAt?: string;
}

export interface WorkspacePayload {
  flows: Flow[];
  anchors: Anchor[];
  windows: WindowDescriptor[];
  workspaceRoot: string;
}
