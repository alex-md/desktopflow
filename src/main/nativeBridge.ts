import { app } from "electron";
import { execFile, spawn } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { promisify } from "node:util";
import type { Flow, FlowRunReport, FlowStep, PermissionSnapshot, RecorderEvent, RecorderStatus, TargetHint, WindowDescriptor } from "../shared/models";

const execFileAsync = promisify(execFile);
const workspaceRoot = path.resolve(process.cwd());
const swiftPackageRoot = workspaceRoot;
const bridgeDebugBinary = path.join(swiftPackageRoot, ".build", "debug", "DesktopflowBridge");
const bridgeReleaseBinary = path.join(swiftPackageRoot, ".build", "release", "DesktopflowBridge");
const packagedBridgeBinary = path.join(process.resourcesPath, "bin", "DesktopflowBridge");

let ensuredBridgePathPromise: Promise<string> | null = null;

type RecorderState = {
  child: ReturnType<typeof spawn>;
  stopPromise: Promise<FlowStep[]>;
  startedAt: string;
  ready: boolean;
  stopRequested: boolean;
  capturedSteps: FlowStep[];
};

type RunState = {
  child: ReturnType<typeof spawn>;
  flowID: string;
  startedAt: string;
  aborted: boolean;
};

let recorderState: RecorderState | null = null;
let runState: RunState | null = null;

const broadcastRecorderEvent = (event: RecorderEvent) => {
  globalThis.__desktopflowRecorderBroadcast?.(event);
};

const parseJson = <T>(raw: string): T => JSON.parse(raw) as T;

const clearRecorderState = (state: RecorderState) => {
  if (recorderState === state) {
    recorderState = null;
  }
};

const forceStopRecorderState = (state: RecorderState, message = "Recording was force-stopped."): FlowStep[] => {
  clearRecorderState(state);

  if (state.child.exitCode === null && state.child.signalCode === null) {
    state.child.kill("SIGTERM");
  }

  broadcastRecorderEvent({
    type: "stopped",
    message,
    count: state.capturedSteps.length,
    steps: state.capturedSteps
  });

  return state.capturedSteps;
};

const getLiveRecorderState = (): RecorderState | null => {
  if (recorderState && (recorderState.child.exitCode !== null || recorderState.child.signalCode !== null)) {
    recorderState = null;
  }

  return recorderState;
};

const bridgeWorkingDirectory = () => (app.isPackaged ? process.resourcesPath : swiftPackageRoot);

const buildBridge = async (): Promise<string> => {
  if (app.isPackaged) {
    if (existsSync(packagedBridgeBinary)) {
      return packagedBridgeBinary;
    }

    throw new Error("DesktopflowBridge is missing from the packaged app resources.");
  }

  if (existsSync(bridgeDebugBinary)) {
    return bridgeDebugBinary;
  }

  if (existsSync(bridgeReleaseBinary)) {
    return bridgeReleaseBinary;
  }

  await execFileAsync("swift", ["build", "--product", "DesktopflowBridge"], {
    cwd: swiftPackageRoot,
    maxBuffer: 10 * 1024 * 1024
  });

  if (existsSync(bridgeDebugBinary)) {
    return bridgeDebugBinary;
  }

  if (existsSync(bridgeReleaseBinary)) {
    return bridgeReleaseBinary;
  }

  throw new Error("DesktopflowBridge built successfully but no bridge binary was found.");
};

const ensureBridgePath = async (): Promise<string> => {
  ensuredBridgePathPromise ??= buildBridge().catch((error) => {
    ensuredBridgePathPromise = null;
    throw error;
  });

  return ensuredBridgePathPromise;
};

const runBridgeCommand = async (args: string[]): Promise<string> => {
  const binary = await ensureBridgePath();

  try {
    const { stdout } = await execFileAsync(binary, args, {
      cwd: bridgeWorkingDirectory(),
      maxBuffer: 10 * 1024 * 1024
    });
    return stdout.trim();
  } catch (error) {
    const message =
      error && typeof error === "object" && "stderr" in error && typeof error.stderr === "string" && error.stderr.trim().length > 0
        ? error.stderr.trim()
        : error instanceof Error
          ? error.message
          : "Bridge command failed.";
    throw new Error(message);
  }
};

export const listNativeWindows = async (): Promise<WindowDescriptor[]> => {
  const stdout = await runBridgeCommand(["list-windows"]);
  return parseJson<WindowDescriptor[]>(stdout);
};

export const getPermissionSnapshot = async (): Promise<PermissionSnapshot> => {
  const stdout = await runBridgeCommand(["permissions"]);
  return parseJson<PermissionSnapshot>(stdout);
};

export const getNativeRecorderStatus = (): RecorderStatus => {
  const state = getLiveRecorderState();
  if (!state) {
    return {
      active: false,
      ready: false
    };
  }

  return {
    active: true,
    ready: state.ready,
    startedAt: state.startedAt
  };
};

export const runNativeFlow = async (workspaceDataRoot: string, flow: Flow): Promise<FlowRunReport> => {
  if (runState) {
    throw new Error("A native flow run is already in progress.");
  }

  const binary = await ensureBridgePath();
  const child = spawn(binary, ["run-flow-json", workspaceDataRoot, JSON.stringify(flow)], {
    cwd: bridgeWorkingDirectory(),
    stdio: ["ignore", "pipe", "pipe"]
  });

  const startedAt = new Date().toISOString();
  runState = {
    child,
    flowID: flow.id,
    startedAt,
    aborted: false
  };

  return await new Promise<FlowRunReport>((resolve, reject) => {
    let stdout = "";
    let stderr = "";

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => {
      stdout += chunk;
    });

    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk: string) => {
      stderr += chunk;
    });

    child.on("error", (error) => {
      runState = null;
      reject(error);
    });

    child.on("close", (code) => {
      const current = runState;
      runState = null;

      if (current?.aborted) {
        resolve({
          flowID: flow.id,
          startedAt,
          finishedAt: new Date().toISOString(),
          status: "aborted",
          stopReason: "Playback aborted.",
          stepResults: []
        });
        return;
      }

      if (code !== 0) {
        reject(new Error(stderr.trim() || `Native flow run exited with code ${code ?? "unknown"}.`));
        return;
      }

      resolve(parseJson<FlowRunReport>(stdout.trim()));
    });
  });
};

export const abortNativeFlow = async (flowID: string): Promise<boolean> => {
  if (!runState || runState.flowID !== flowID) {
    return false;
  }

  runState.aborted = true;
  runState.child.kill("SIGTERM");
  return true;
};

export const startNativeRecording = async (targetHint: TargetHint): Promise<void> => {
  const permissions = await getPermissionSnapshot();
  if (!permissions.accessibility || !permissions.inputMonitoring) {
    const missingPermissions = [
      !permissions.accessibility ? "Accessibility" : null,
      !permissions.inputMonitoring ? "Input Monitoring" : null
    ].filter(Boolean);
    throw new Error(`Grant ${missingPermissions.join(" and ")} access in macOS Settings before recording.`);
  }

  if (getLiveRecorderState()) {
    throw new Error("Recording is already in progress.");
  }

  const binary = await ensureBridgePath();
  const child = spawn(binary, ["record", JSON.stringify(targetHint)], {
    cwd: bridgeWorkingDirectory(),
    stdio: ["pipe", "pipe", "pipe"]
  });

  let stdoutBuffer = "";
  let stderrBuffer = "";
  let stopResolved = false;
  let readyResolved = false;
  let failed = false;
  const state: RecorderState = {
    child,
    stopPromise: Promise.resolve([]),
    startedAt: new Date().toISOString(),
    ready: false,
    stopRequested: false,
    capturedSteps: []
  };

  let resolveReady!: () => void;
  let rejectReady!: (error: Error) => void;

  const readyPromise = new Promise<void>((resolve, reject) => {
    resolveReady = resolve;
    rejectReady = reject;
  });

  const failRecordingStart = (error: Error, broadcast = true) => {
    if (failed) {
      return;
    }

    failed = true;
    clearRecorderState(state);

    if (!readyResolved) {
      readyResolved = true;
      rejectReady(error);
    }

    if (broadcast) {
      broadcastRecorderEvent({ type: "error", message: error.message });
    }
  };

  const stopPromise = new Promise<FlowStep[]>((resolve, reject) => {
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => {
      stdoutBuffer += chunk;

      while (stdoutBuffer.includes("\n")) {
        const newlineIndex = stdoutBuffer.indexOf("\n");
        const line = stdoutBuffer.slice(0, newlineIndex).trim();
        stdoutBuffer = stdoutBuffer.slice(newlineIndex + 1);

        if (!line) {
          continue;
        }

        const event = parseJson<RecorderEvent>(line);

        if (event.type === "ready" && !readyResolved) {
          state.ready = true;
          readyResolved = true;
          resolveReady();
        }

        if (event.type === "stepCaptured" && event.step) {
          state.capturedSteps.push(event.step);
        }

        if (event.type === "stopped") {
          const resolvedSteps = event.steps && event.steps.length > 0 ? event.steps : state.capturedSteps;
          stopResolved = true;
          clearRecorderState(state);
          broadcastRecorderEvent({
            ...event,
            count: resolvedSteps.length,
            steps: resolvedSteps
          });
          resolve(resolvedSteps);
          continue;
        }

        broadcastRecorderEvent(event);
      }
    });

    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk: string) => {
      stderrBuffer += chunk;
    });

    child.on("error", (error) => {
      failRecordingStart(error, false);

      if (!stopResolved) {
        reject(error);
      }
    });

    child.on("close", (code) => {
      if (stopResolved) {
        return;
      }

      if (state.stopRequested) {
        stopResolved = true;
        clearRecorderState(state);
        resolve(state.capturedSteps);
        return;
      }

      const message = stderrBuffer.trim() || `Recorder exited with code ${code ?? "unknown"}.`;
      const error = new Error(message);
      failRecordingStart(error);

      reject(error);
    });
  });

  state.stopPromise = stopPromise;
  recorderState = state;
  await readyPromise;
};

export const stopNativeRecording = async (): Promise<FlowStep[]> => {
  const state = getLiveRecorderState();
  if (!state) {
    return [];
  }

  state.stopRequested = true;

  if (!state.child.stdin) {
    return forceStopRecorderState(state, "Recorder stdin was unavailable. Recording was force-stopped.");
  }

  state.child.stdin.write("stop\n");
  state.child.stdin.end();

  let stopTimeout: NodeJS.Timeout | undefined;
  const timeoutPromise = new Promise<FlowStep[]>((resolve) => {
    stopTimeout = setTimeout(() => {
      resolve(forceStopRecorderState(state));
    }, 1500);
  });

  try {
    return await Promise.race([state.stopPromise, timeoutPromise]);
  } finally {
    if (stopTimeout) {
      clearTimeout(stopTimeout);
    }
  }
};

declare global {
  var __desktopflowRecorderBroadcast: ((event: RecorderEvent) => void) | undefined;
}
