import type { Flow, FlowRunReport, RunStatus, RunStepResult } from "../shared/models";

const activeRuns = new Map<string, AbortController>();

const sleep = async (milliseconds: number, signal?: AbortSignal) =>
  new Promise<void>((resolve, reject) => {
    if (signal?.aborted) {
      reject(new Error("aborted"));
      return;
    }

    const timer = setTimeout(() => {
      cleanup();
      resolve();
    }, milliseconds);

    const onAbort = () => {
      clearTimeout(timer);
      cleanup();
      reject(new Error("aborted"));
    };

    const cleanup = () => signal?.removeEventListener("abort", onAbort);
    signal?.addEventListener("abort", onAbort, { once: true });
  });

const asFailureStatus = (reason: string): RunStatus => (reason === "aborted" ? "aborted" : "failed");

export const abortFlowRun = async (flowID: string) => {
  activeRuns.get(flowID)?.abort();
};

export const runFlow = async (flow: Flow): Promise<FlowRunReport> => {
  const controller = new AbortController();
  const startedAt = new Date().toISOString();
  const stepResults: RunStepResult[] = [];
  activeRuns.set(flow.id, controller);

  try {
    for (const step of flow.steps.filter((item) => item.enabled)) {
      const stepStartedAt = new Date().toISOString();

      if (step.type === "waitForAnchor" || step.preconditions.length > 0 || step.postconditions.length > 0) {
        const reason = "Anchor-based playback is not wired in the Electron port yet.";
        stepResults.push({
          stepID: step.id,
          startedAt: stepStartedAt,
          finishedAt: new Date().toISOString(),
          status: "failed",
          reason,
          attempts: 1
        });

        return {
          flowID: flow.id,
          startedAt,
          finishedAt: new Date().toISOString(),
          status: "failed",
          stopReason: reason,
          stepResults
        };
      }

      const pause = step.type === "wait" ? Math.min(step.params.durationMs ?? 0, 1500) : 180;
      await sleep(pause, controller.signal);

      stepResults.push({
        stepID: step.id,
        startedAt: stepStartedAt,
        finishedAt: new Date().toISOString(),
        status: "succeeded",
        attempts: step.retryPolicy?.maxAttempts ?? 1
      });
    }

    return {
      flowID: flow.id,
      startedAt,
      finishedAt: new Date().toISOString(),
      status: "succeeded",
      stepResults
    };
  } catch (error) {
    const reason = error instanceof Error ? error.message : "failed";
    return {
      flowID: flow.id,
      startedAt,
      finishedAt: new Date().toISOString(),
      status: asFailureStatus(reason),
      stopReason: reason === "aborted" ? "Playback aborted." : reason,
      stepResults
    };
  } finally {
    activeRuns.delete(flow.id);
  }
};
