import { execFile, spawn } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { promisify } from "node:util";
import type { FlowRunReport, FlowStep, PermissionSnapshot, RecorderEvent, TargetHint, WindowDescriptor } from "../shared/models";

const execFileAsync = promisify(execFile);
const workspaceRoot = path.resolve(process.cwd());
const swiftPackageRoot = workspaceRoot;
const bridgeDebugBinary = path.join(swiftPackageRoot, ".build", "debug", "DesktopflowBridge");
const bridgeReleaseBinary = path.join(swiftPackageRoot, ".build", "release", "DesktopflowBridge");

let ensuredBridgePathPromise: Promise<string> | null = null;

type RecorderState = {
  child: ReturnType<typeof spawn>;
  stopPromise: Promise<FlowStep[]>;
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

const buildBridge = async (): Promise<string> => {
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
      cwd: swiftPackageRoot,
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

export const runNativeFlow = async (workspaceDataRoot: string, flowID: string): Promise<FlowRunReport> => {
  if (runState) {
    throw new Error("A native flow run is already in progress.");
  }

  const binary = await ensureBridgePath();
  const child = spawn(binary, ["run-flow", workspaceDataRoot, flowID], {
    cwd: swiftPackageRoot,
    stdio: ["ignore", "pipe", "pipe"]
  });

  const startedAt = new Date().toISOString();
  runState = {
    child,
    flowID,
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
          flowID,
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
  if (recorderState) {
    throw new Error("Recording is already in progress.");
  }

  const binary = await ensureBridgePath();
  const child = spawn(binary, ["record", JSON.stringify(targetHint)], {
    cwd: swiftPackageRoot,
    stdio: ["pipe", "pipe", "pipe"]
  });

  let stdoutBuffer = "";
  let stderrBuffer = "";
  let resolved = false;

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
        broadcastRecorderEvent(event);

        if (event.type === "stopped") {
          resolved = true;
          resolve(event.steps ?? []);
        }
      }
    });

    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk: string) => {
      stderrBuffer += chunk;
    });

    child.on("error", (error) => {
      if (!resolved) {
        reject(error);
      }
    });

    child.on("close", (code) => {
      if (resolved) {
        return;
      }

      const message = stderrBuffer.trim() || `Recorder exited with code ${code ?? "unknown"}.`;
      broadcastRecorderEvent({ type: "error", message });
      reject(new Error(message));
    });
  });

  recorderState = { child, stopPromise };
};

export const stopNativeRecording = async (): Promise<FlowStep[]> => {
  if (!recorderState) {
    return [];
  }

  const state = recorderState;
  recorderState = null;
  if (!state.child.stdin) {
    throw new Error("Recorder stdin is unavailable.");
  }
  state.child.stdin.write("stop\n");
  state.child.stdin.end();
  return state.stopPromise;
};

declare global {
  var __desktopflowRecorderBroadcast: ((event: RecorderEvent) => void) | undefined;
}
