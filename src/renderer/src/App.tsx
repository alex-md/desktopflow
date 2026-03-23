import { useEffect, useMemo, useState } from "react";
import type {
  Anchor,
  Flow,
  FlowRunReport,
  FlowStep,
  MouseButton,
  PermissionSnapshot,
  RecorderEvent,
  RecorderStatus,
  StepType,
  WorkspacePayload
} from "../../shared/models";
import { mouseButtons, stepTypes } from "../../shared/models";

type AppSection = "recorder" | "editor" | "runner" | "permissions";

const sections: Array<{ id: AppSection; label: string; eyebrow: string }> = [
  { id: "recorder", label: "Recorder", eyebrow: "Capture" },
  { id: "editor", label: "Flow Editor", eyebrow: "Authoring" },
  { id: "runner", label: "Runner", eyebrow: "Playback" },
  { id: "permissions", label: "Permissions", eyebrow: "System" }
];

const emptyWorkspace: WorkspacePayload = {
  flows: [],
  anchors: [],
  windows: [],
  workspaceRoot: ""
};

const createId = () => globalThis.crypto.randomUUID();
const emptyPermissions: PermissionSnapshot = {
  accessibility: false,
  inputMonitoring: false,
  screenRecording: false
};

const cloneFlow = (flow: Flow | null): Flow | null => (flow ? JSON.parse(JSON.stringify(flow)) : null);

const normalizeOptional = (value: string) => {
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
};

const createStep = (type: StepType, ordinal: number): FlowStep => {
  switch (type) {
    case "wait":
      return {
        id: createId(),
        ordinal,
        type,
        params: { modifiers: [], durationMs: 500 },
        enabled: true,
        preconditions: [],
        postconditions: []
      };
    case "waitForAnchor":
      return {
        id: createId(),
        ordinal,
        type,
        params: { modifiers: [], pollIntervalMs: 120 },
        enabled: true,
        timeoutMs: 5000,
        preconditions: [],
        postconditions: []
      };
    case "clickAt":
      return {
        id: createId(),
        ordinal,
        type,
        params: {
          modifiers: [],
          button: "left",
          point: { x: 0.5, y: 0.5 }
        },
        enabled: true,
        preconditions: [],
        postconditions: []
      };
    case "scrollAt":
      return {
        id: createId(),
        ordinal,
        type,
        params: {
          modifiers: [],
          point: { x: 0.5, y: 0.5 },
          deltaX: 0,
          deltaY: -6
        },
        enabled: true,
        preconditions: [],
        postconditions: []
      };
    case "dragTo":
      return {
        id: createId(),
        ordinal,
        type,
        params: {
          modifiers: [],
          button: "left",
          point: { x: 0.35, y: 0.5 },
          endPoint: { x: 0.7, y: 0.5 },
          durationMs: 350
        },
        enabled: true,
        preconditions: [],
        postconditions: []
      };
    case "pressKey":
      return {
        id: createId(),
        ordinal,
        type,
        params: {
          modifiers: [],
          keyCode: "SPACE"
        },
        enabled: true,
        preconditions: [],
        postconditions: []
      };
    case "checkpointScreenshot":
      return {
        id: createId(),
        ordinal,
        type,
        params: {
          modifiers: [],
          label: "checkpoint"
        },
        enabled: true,
        preconditions: [],
        postconditions: []
      };
    default:
      return {
        id: createId(),
        ordinal,
        type,
        params: { modifiers: [] },
        enabled: true,
        preconditions: [],
        postconditions: []
      };
  }
};

const createFlow = (): Flow => {
  const now = new Date().toISOString();
  return {
    id: createId(),
    name: "Untitled Flow",
    description: "New flow",
    targetHint: {},
    defaultTimeoutMs: 5000,
    createdAt: now,
    updatedAt: now,
    version: 1,
    steps: [createStep("attachWindow", 0), createStep("focusWindow", 1)]
  };
};

const renumberSteps = (steps: FlowStep[]): FlowStep[] =>
  steps.map((step, index) => ({
    ...step,
    ordinal: index
  }));

const fmtDate = (value?: string) => {
  if (!value) {
    return "N/A";
  }

  try {
    return new Intl.DateTimeFormat(undefined, {
      dateStyle: "medium",
      timeStyle: "short"
    }).format(new Date(value));
  } catch {
    return value;
  }
};

const stepSummary = (step: FlowStep, anchors: Anchor[]) => {
  switch (step.type) {
    case "attachWindow":
      return "Bind the configured target window.";
    case "focusWindow":
      return "Bring the target window to the foreground.";
    case "wait":
      return `${step.params.durationMs ?? 0} ms fixed wait.`;
    case "waitForAnchor": {
      const anchor = anchors.find((item) => item.id === step.params.anchorID);
      return anchor
        ? `Wait for anchor ${anchor.name} every ${step.params.pollIntervalMs ?? 120} ms.`
        : "Wait for an anchor.";
    }
    case "clickAt":
      return `Click ${(step.params.point?.x ?? 0.5).toFixed(3)}, ${(step.params.point?.y ?? 0.5).toFixed(3)} with ${step.params.button ?? "left"} button.`;
    case "scrollAt":
      return `Scroll at ${(step.params.point?.x ?? 0.5).toFixed(3)}, ${(step.params.point?.y ?? 0.5).toFixed(3)} by dx ${step.params.deltaX ?? 0}, dy ${step.params.deltaY ?? 0}.`;
    case "dragTo":
      return `Drag from ${(step.params.point?.x ?? 0.35).toFixed(3)}, ${(step.params.point?.y ?? 0.5).toFixed(3)} to ${(step.params.endPoint?.x ?? 0.7).toFixed(3)}, ${(step.params.endPoint?.y ?? 0.5).toFixed(3)} with ${step.params.button ?? "left"} button.`;
    case "pressKey":
      return `Press ${step.params.modifiers.length > 0 ? `${step.params.modifiers.join("+")}+` : ""}${step.params.keyCode ?? "UNKNOWN"}.`;
    case "checkpointScreenshot":
      return `Capture screenshot '${step.params.label ?? "checkpoint"}'.`;
    default:
      return step.type;
  }
};

const stepDetail = (step: FlowStep, anchors: Anchor[]) => {
  if (step.type === "pressKey") {
    const modifiers = step.params.modifiers.length > 0 ? `${step.params.modifiers.join("+")}+` : "";
    return `Press ${modifiers}${step.params.keyCode ?? "UNKNOWN"}.`;
  }

  return stepSummary(step, anchors);
};

const stepPaletteSummary = (type: StepType) => {
  switch (type) {
    case "attachWindow":
      return "Match the target application window.";
    case "focusWindow":
      return "Bring the matched window forward.";
    case "wait":
      return "Pause for a fixed duration.";
    case "waitForAnchor":
      return "Pause until an anchor appears.";
    case "clickAt":
      return "Click a normalized position.";
    case "scrollAt":
      return "Scroll at the pointer location.";
    case "dragTo":
      return "Click, hold, and drag between two points.";
    case "pressKey":
      return "Send a keyboard shortcut or key.";
    case "checkpointScreenshot":
      return "Capture a debug screenshot checkpoint.";
    default:
      return formatStepType(type);
  }
};

const formatStepType = (type: StepType) =>
  type
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/^./, (value) => value.toUpperCase());

const PreviewSurface = ({ flow }: { flow: Flow }) => (
  <div className="preview-surface">
    <div className="preview-window">
      <div className="preview-toolbar">
        <span>{flow.targetHint.appName ?? flow.name}</span>
      </div>
      <div className="preview-screen">
        {flow.steps
          .filter((step) => step.type === "clickAt" && step.params.point)
          .map((step) => (
            <span
              className="preview-dot"
              key={step.id}
              style={{
                left: `${(step.params.point?.x ?? 0) * 100}%`,
                top: `${(step.params.point?.y ?? 0) * 100}%`
              }}
            />
          ))}
      </div>
    </div>
  </div>
);

const Header = ({
  eyebrow,
  title,
  subtitle,
  meta
}: {
  eyebrow: string;
  title: string;
  subtitle: string;
  meta?: string;
}) => (
  <header className="section-header">
    <div className="section-header-copy">
      <p>{eyebrow}</p>
      <div>
        <h1>{title}</h1>
        <span>{subtitle}</span>
      </div>
    </div>
    {meta ? <div className="section-meta">{meta}</div> : null}
  </header>
);

const KeyValue = ({ label, value }: { label: string; value: string }) => (
  <div className="key-value">
    <span>{label}</span>
    <strong>{value}</strong>
  </div>
);

const permissionLabel = (granted: boolean) => (granted ? "Granted" : "Missing");

const getErrorMessage = (error: unknown, fallback: string) => {
  if (!(error instanceof Error)) {
    return fallback;
  }

  return error.message.replace(/^Error invoking remote method '[^']+': Error: /, "");
};

export default function App() {
  const [workspace, setWorkspace] = useState<WorkspacePayload>(emptyWorkspace);
  const [selectedSection, setSelectedSection] = useState<AppSection>("recorder");
  const [selectedFlowId, setSelectedFlowId] = useState<string | null>(null);
  const [selectedEditorStepId, setSelectedEditorStepId] = useState<string | null>(null);
  const [editorDraft, setEditorDraft] = useState<Flow | null>(null);
  const [editorSnapshot, setEditorSnapshot] = useState<Flow | null>(null);
  const [editorStatus, setEditorStatus] = useState("Loading workspace...");
  const [lastError, setLastError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [selectedWindowId, setSelectedWindowId] = useState<string | null>(null);
  const [recorderFlowName, setRecorderFlowName] = useState("Recorded Flow");
  const [recordedSteps, setRecordedSteps] = useState<FlowStep[]>([]);
  const [isRecording, setIsRecording] = useState(false);
  const [isRecorderPending, setIsRecorderPending] = useState(false);
  const [recorderStatus, setRecorderStatus] = useState("Idle");
  const [isRunningFlow, setIsRunningFlow] = useState(false);
  const [runnerStatus, setRunnerStatus] = useState("Idle");
  const [lastRunReport, setLastRunReport] = useState<FlowRunReport | null>(null);
  const [permissions, setPermissions] = useState<PermissionSnapshot>(emptyPermissions);
  const grantedPermissionCount =
    Number(permissions.accessibility) +
    Number(permissions.inputMonitoring) +
    Number(permissions.screenRecording);
  const allPermissionsGranted = grantedPermissionCount === 3;

  const selectedFlow = useMemo(
    () => workspace.flows.find((flow) => flow.id === selectedFlowId) ?? workspace.flows[0] ?? null,
    [workspace.flows, selectedFlowId]
  );

  const selectedWindow = useMemo(
    () => workspace.windows.find((window) => window.id === selectedWindowId) ?? workspace.windows[0] ?? null,
    [workspace.windows, selectedWindowId]
  );

  const selectedEditorStep = useMemo(
    () => editorDraft?.steps.find((step) => step.id === selectedEditorStepId) ?? editorDraft?.steps[0] ?? null,
    [editorDraft, selectedEditorStepId]
  );

  const editorIsDirty = useMemo(
    () => JSON.stringify(editorDraft) !== JSON.stringify(editorSnapshot),
    [editorDraft, editorSnapshot]
  );

  const hydrateEditor = (flow: Flow | null) => {
    const draft = cloneFlow(flow);
    setEditorDraft(draft);
    setEditorSnapshot(cloneFlow(flow));
    setSelectedEditorStepId(draft?.steps[0]?.id ?? null);
    setEditorStatus(draft ? `Editing '${draft.name}'.` : "Create or select a flow to edit.");
  };

  const loadPermissions = async () => {
    try {
      setPermissions(await window.desktopflow.getPermissions());
    } catch (error) {
      setLastError(error instanceof Error ? error.message : "Failed to load permissions.");
    }
  };

  const loadWorkspace = async (preferredFlowId?: string | null) => {
    setIsLoading(true);

    try {
      const payload = await window.desktopflow.loadWorkspace();
      setWorkspace(payload);
      const nextFlowId =
        preferredFlowId && payload.flows.some((flow) => flow.id === preferredFlowId)
          ? preferredFlowId
          : payload.flows[0]?.id ?? null;
      setSelectedFlowId(nextFlowId);
      setSelectedWindowId((current) =>
        current && payload.windows.some((window) => window.id === current) ? current : payload.windows[0]?.id ?? null
      );
      const selected = payload.flows.find((flow) => flow.id === nextFlowId) ?? null;
      hydrateEditor(selected);
      setLastError(null);
    } catch (error) {
      setLastError(error instanceof Error ? error.message : "Failed to load workspace.");
    } finally {
      setIsLoading(false);
    }
  };

  const applyRecorderStatus = (status: RecorderStatus) => {
    setIsRecording(status.active);
    setIsRecorderPending(status.active && !status.ready);

    if (!status.active) {
      setRecorderStatus("Idle");
      return;
    }

    setRecorderStatus(
      status.ready
        ? "Native recorder is already live. Stop it before starting a new session."
        : "Native recorder is still starting. Wait for it to become ready or close the app window to reset it."
    );
  };

  const loadRecorderStatus = async () => {
    try {
      applyRecorderStatus(await window.desktopflow.getRecorderStatus());
    } catch (error) {
      setLastError(getErrorMessage(error, "Failed to load recorder status."));
    }
  };

  useEffect(() => {
    void loadWorkspace();
    void loadPermissions();
    void loadRecorderStatus();
  }, []);

  useEffect(() => {
    const unsubscribe = window.desktopflow.onRecorderEvent((event: RecorderEvent) => {
      if (event.type === "ready") {
        setIsRecording(true);
        setIsRecorderPending(false);
        setRecorderStatus("Native recorder is live. Interact with the selected app.");
        return;
      }

      if (event.type === "stepCaptured") {
        if (event.step) {
          setRecordedSteps((current) => [...current, event.step as FlowStep]);
        }
        setRecorderStatus(event.message ?? `Captured ${event.count ?? 0} steps.`);
        return;
      }

      if (event.type === "stopped") {
        setIsRecording(false);
        setIsRecorderPending(false);
        setRecordedSteps(event.steps ?? []);
        setRecorderStatus(event.message ?? "Recording stopped.");
        return;
      }

      setIsRecording(false);
      setIsRecorderPending(false);
      setRecorderStatus(event.message ?? "Recording failed.");
    });

    return unsubscribe;
  }, []);

  const selectFlow = (flowId: string | null) => {
    if (flowId === selectedFlowId) {
      return;
    }

    if (!confirmReplaceEditorDraft()) {
      return;
    }

    setSelectedFlowId(flowId);
    const flow = workspace.flows.find((item) => item.id === flowId) ?? null;
    hydrateEditor(flow);
  };

  const mutateEditorDraft = (updater: (draft: Flow) => Flow) => {
    setEditorDraft((current) => {
      if (!current) {
        return current;
      }

      const next = updater(cloneFlow(current) as Flow);
      next.updatedAt = new Date().toISOString();
      return {
        ...next,
        steps: renumberSteps(next.steps)
      };
    });
  };

  const saveEditorDraft = async () => {
    if (!editorDraft) {
      return;
    }

    try {
      const flowToSave: Flow = {
        ...editorDraft,
        updatedAt: new Date().toISOString(),
        version: (editorSnapshot?.version ?? editorDraft.version) + 1,
        steps: renumberSteps(editorDraft.steps)
      };

      const payload = await window.desktopflow.saveFlow(flowToSave);
      setWorkspace(payload);
      setSelectedFlowId(flowToSave.id);
      hydrateEditor(flowToSave);
      setLastError(null);
      setEditorStatus(`Saved '${flowToSave.name}'.`);
    } catch (error) {
      const message = getErrorMessage(error, "Failed to save the current flow.");
      setLastError(message);
      setEditorStatus(message);
    }
  };

  const deleteSelectedFlow = async () => {
    if (!selectedFlow) {
      return;
    }

    if (!window.confirm(`Delete '${selectedFlow.name}'?`)) {
      return;
    }

    try {
      const payload = await window.desktopflow.deleteFlow(selectedFlow.id);
      setWorkspace(payload);
      const nextFlow = payload.flows[0] ?? null;
      setSelectedFlowId(nextFlow?.id ?? null);
      hydrateEditor(nextFlow);
      setLastError(null);
      setEditorStatus(nextFlow ? `Editing '${nextFlow.name}'.` : "Create or select a flow to edit.");
    } catch (error) {
      const message = getErrorMessage(error, "Failed to delete the selected flow.");
      setLastError(message);
      setEditorStatus(message);
    }
  };

  const refreshWindows = async () => {
    try {
      const payload = await window.desktopflow.loadWorkspace();
      setWorkspace(payload);
      setSelectedWindowId((current) =>
        current && payload.windows.some((window) => window.id === current) ? current : payload.windows[0]?.id ?? null
      );
      setLastError(null);
      setRecorderStatus(
        payload.windows.length > 0
          ? `Loaded ${payload.windows.length} configured target window${payload.windows.length === 1 ? "" : "s"}.`
          : "No configured target windows were found."
      );
    } catch (error) {
      const message = getErrorMessage(error, "Failed to refresh target windows.");
      setLastError(message);
      setRecorderStatus(message);
    }
  };

  const startRecording = async () => {
    if (!selectedWindow) {
      setRecorderStatus("Choose a target window first.");
      return;
    }

    try {
      const livePermissions = await window.desktopflow.getPermissions();
      setPermissions(livePermissions);
      if (!livePermissions.accessibility || !livePermissions.inputMonitoring) {
        setRecorderStatus("Grant Accessibility and Input Monitoring in macOS Settings before recording.");
        return;
      }
    } catch (error) {
      setRecorderStatus(getErrorMessage(error, "Failed to verify permissions."));
      return;
    }

    setRecordedSteps([]);
    setIsRecorderPending(true);
    setRecorderStatus(`Starting native recorder for ${selectedWindow.appName} / ${selectedWindow.title}...`);

    try {
      await window.desktopflow.startRecording({
        bundleID: selectedWindow.bundleID,
        appName: selectedWindow.appName,
        windowTitleContains: selectedWindow.title,
        ownerPID: selectedWindow.ownerPID
      });
    } catch (error) {
      setIsRecording(false);
      setIsRecorderPending(false);
      const message = getErrorMessage(error, "Failed to start recording.");
      setRecorderStatus(message);
      if (message === "Recording is already in progress.") {
        void loadRecorderStatus();
      }
    }
  };

  const stopRecording = async () => {
    try {
      const steps = await window.desktopflow.stopRecording();
      const finalSteps = steps.length > 0 ? steps : recordedSteps;
      setRecordedSteps(finalSteps);
      setIsRecording(false);
      setIsRecorderPending(false);
      if (finalSteps.length > 0) {
        setRecorderStatus(`Recording stopped with ${finalSteps.length} captured steps.`);
      }
    } catch (error) {
      setIsRecording(false);
      setIsRecorderPending(false);
      setRecorderStatus(getErrorMessage(error, "Failed to stop recording."));
    }
  };

  const saveRecording = async () => {
    if (!selectedWindow || recordedSteps.length === 0) {
      setRecorderStatus("Record at least one click, drag, scroll, or key press before saving.");
      return;
    }

    const now = new Date().toISOString();
    const trimmedName = recorderFlowName.trim() || "Recorded Flow";
    const flow: Flow = {
      id: createId(),
      name: trimmedName,
      description: `Recorded from ${selectedWindow.appName} / ${selectedWindow.title}`,
      targetHint: {
        bundleID: selectedWindow.bundleID,
        appName: selectedWindow.appName,
        windowTitleContains: selectedWindow.title,
        ownerPID: selectedWindow.ownerPID
      },
      defaultTimeoutMs: 5000,
      createdAt: now,
      updatedAt: now,
      version: 1,
      steps: renumberSteps([
        createStep("attachWindow", 0),
        createStep("focusWindow", 1),
        ...recordedSteps.map((step) => ({
          ...step,
          id: createId()
        }))
      ])
    };

    try {
      const payload = await window.desktopflow.saveFlow(flow);
      setWorkspace(payload);
      setSelectedFlowId(flow.id);
      hydrateEditor(flow);
      setRecordedSteps([]);
      setIsRecording(false);
      setSelectedSection("editor");
      setLastError(null);
      setRecorderStatus(`Saved ${flow.steps.length - 2} recorded steps to '${flow.name}'.`);
    } catch (error) {
      const message = getErrorMessage(error, "Failed to save the recorded flow.");
      setLastError(message);
      setRecorderStatus(message);
    }
  };

  const runSelectedFlow = async () => {
    if (!selectedFlow) {
      setRunnerStatus("Select a flow first.");
      return;
    }

    setIsRunningFlow(true);
    setRunnerStatus(`Running '${selectedFlow.name}'...`);
    setLastRunReport(null);

    try {
      const report = await window.desktopflow.runFlow(selectedFlow);
      setLastRunReport(report);
      setRunnerStatus(report.status === "succeeded" ? "Playback finished successfully." : report.stopReason ?? "Playback failed.");
    } catch (error) {
      setRunnerStatus(error instanceof Error ? error.message : "Playback failed.");
    } finally {
      setIsRunningFlow(false);
    }
  };

  const abortRunningFlow = async () => {
    if (!selectedFlow) {
      return;
    }

    try {
      const aborted = await window.desktopflow.abortFlow(selectedFlow.id);
      setLastError(null);
      setRunnerStatus(aborted ? "Abort requested." : "No active native run to abort.");
    } catch (error) {
      const message = getErrorMessage(error, "Failed to abort the current run.");
      setLastError(message);
      setRunnerStatus(message);
    }
  };

  const toggleModifier = (modifier: string) => {
    mutateEditorDraft((draft) => {
      const step = draft.steps.find((item) => item.id === selectedEditorStep?.id);
      if (!step) {
        return draft;
      }

      const nextModifiers = step.params.modifiers.includes(modifier)
        ? step.params.modifiers.filter((item) => item !== modifier)
        : [...step.params.modifiers, modifier];

      step.params.modifiers = nextModifiers;
      return draft;
    });
  };

  const upsertSelectedStep = (updater: (step: FlowStep) => void) => {
    mutateEditorDraft((draft) => {
      const step = draft.steps.find((item) => item.id === selectedEditorStep?.id);
      if (step) {
        updater(step);
      }
      return draft;
    });
  };

  const moveStep = (stepId: string, direction: -1 | 1) => {
    mutateEditorDraft((draft) => {
      const index = draft.steps.findIndex((step) => step.id === stepId);
      const nextIndex = index + direction;

      if (index < 0 || nextIndex < 0 || nextIndex >= draft.steps.length) {
        return draft;
      }

      const nextSteps = [...draft.steps];
      const [step] = nextSteps.splice(index, 1);
      nextSteps.splice(nextIndex, 0, step);
      draft.steps = nextSteps;
      return draft;
    });
  };

  const duplicateStep = (stepId: string) => {
    mutateEditorDraft((draft) => {
      const index = draft.steps.findIndex((step) => step.id === stepId);
      if (index < 0) {
        return draft;
      }

      const copy = cloneFlow({ ...draft, steps: [draft.steps[index]] } as Flow)?.steps[0];
      if (!copy) {
        return draft;
      }

      copy.id = createId();
      draft.steps.splice(index + 1, 0, copy);
      return draft;
    });
  };

  const removeStep = (stepId: string) => {
    mutateEditorDraft((draft) => {
      draft.steps = draft.steps.filter((step) => step.id !== stepId);
      return draft;
    });
    setSelectedEditorStepId((current) => (current === stepId ? editorDraft?.steps.find((step) => step.id !== stepId)?.id ?? null : current));
  };

  const replaceSelectedStepType = (type: StepType) => {
    mutateEditorDraft((draft) => {
      const index = draft.steps.findIndex((step) => step.id === selectedEditorStep?.id);
      if (index < 0) {
        return draft;
      }

      draft.steps[index] = {
        ...createStep(type, draft.steps[index].ordinal),
        id: draft.steps[index].id,
        enabled: draft.steps[index].enabled,
        debugNote: draft.steps[index].debugNote
      };
      return draft;
    });
  };

  const addAction = (type: StepType) => {
    mutateEditorDraft((draft) => {
      draft.steps.push(createStep(type, draft.steps.length));
      return draft;
    });
  };

  const selectedFlowStepIds = new Set(selectedFlow?.steps.map((step) => step.id));
  const activeSection = sections.find((section) => section.id === selectedSection) ?? sections[0];
  const enabledEditorStepCount = editorDraft?.steps.filter((step) => step.enabled).length ?? 0;
  const selectedEditorStepOrdinal = selectedEditorStep ? selectedEditorStep.ordinal + 1 : null;
  const draftExistsInWorkspace = editorDraft ? workspace.flows.some((flow) => flow.id === editorDraft.id) : false;
  const hasUnsavedEditorWork = Boolean(editorDraft) && (!draftExistsInWorkspace || editorIsDirty);
  const canSaveEditorDraft = Boolean(editorDraft) && hasUnsavedEditorWork;
  const runnerCompletion = lastRunReport
    ? `${lastRunReport.stepResults.filter((result) => result.status === "succeeded").length}/${lastRunReport.stepResults.length} complete`
    : "No recent run";
  const workspaceSummary = `${workspace.flows.length} flows • ${workspace.windows.length} targets`;
  const activeFlowSummary = lastError ? lastError : selectedFlow ? `${selectedFlow.name} is currently in focus.` : "Select or create a flow to begin.";

  const confirmReplaceEditorDraft = () => {
    if (!hasUnsavedEditorWork) {
      return true;
    }

    return window.confirm("Discard the current editor changes?");
  };

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (selectedSection !== "editor" || !canSaveEditorDraft) {
        return;
      }

      if (!(event.metaKey || event.ctrlKey) || event.shiftKey || event.altKey || event.key.toLowerCase() !== "s") {
        return;
      }

      event.preventDefault();
      void saveEditorDraft();
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [selectedSection, canSaveEditorDraft, editorDraft, editorSnapshot, workspace.flows]);

  return (
    <div className="shell">
      <aside className="sidebar">
        <nav className="nav-card sidebar-card">
          <div className="card-heading">
            <span className="nav-label">Navigate</span>
            <strong>{activeSection.eyebrow}</strong>
          </div>
          {sections.map((section) => (
            <button
              className={selectedSection === section.id ? "nav-item active" : "nav-item"}
              key={section.id}
              onClick={() => setSelectedSection(section.id)}
              type="button"
            >
              <small>{section.eyebrow}</small>
              <strong>{section.label}</strong>
            </button>
          ))}
        </nav>

        <div className="flow-card sidebar-card">
          <div className="flow-card-header">
            <div className="card-heading">
              <span>Flows</span>
              <p>{workspaceSummary}</p>
            </div>
            <button
              className="ghost small"
              onClick={() => {
                if (!confirmReplaceEditorDraft()) {
                  return;
                }

                const flow = createFlow();
                setSelectedFlowId(flow.id);
                setSelectedSection("editor");
                hydrateEditor(flow);
              }}
              type="button"
            >
              New
            </button>
          </div>
          <div className="flow-list">
            {workspace.flows.length === 0 ? (
              <div className="empty-note">
                <strong>No flows yet</strong>
                <span>Create a draft to start building the workspace.</span>
              </div>
            ) : (
              workspace.flows.map((flow) => (
                <button
                  className={selectedFlow?.id === flow.id ? "flow-item active" : "flow-item"}
                  key={flow.id}
                  onClick={() => selectFlow(flow.id)}
                  type="button"
                >
                  <strong>{flow.name}</strong>
                  <span>{flow.description}</span>
                  <small>{flow.steps.length} steps</small>
                </button>
              ))
            )}
          </div>
        </div>
      </aside>

      <main className="content">
        <div className="topbar">
          <div className="topbar-main">
            <div className="topbar-copy">
              <span>{activeSection.eyebrow}</span>
              <strong>{activeSection.label}</strong>
              <p>{activeFlowSummary}</p>
            </div>
          </div>
        </div>

        {selectedSection === "recorder" && (
          <section className="page">
            <Header
              eyebrow="Capture"
              title="Recorder"
              subtitle="Capture real clicks, drags, scrolls, and keys from the selected macOS window through the Swift bridge."
              meta={`${recordedSteps.length} captured steps`}
            />

            <div className="panel-grid single">
              <article className="panel">
                <div className="panel-header">
                  <div>
                    <p>Target</p>
                    <h2>Recording Setup</h2>
                  </div>
                </div>

                <label className="field">
                  <span>Target Window</span>
                  <select disabled={workspace.windows.length === 0} value={selectedWindowId ?? ""} onChange={(event) => setSelectedWindowId(event.target.value)}>
                    {workspace.windows.length === 0 ? (
                      <option value="">No target windows available</option>
                    ) : (
                      workspace.windows.map((window) => (
                        <option key={window.id} value={window.id}>
                          {window.appName} · {window.title}
                        </option>
                      ))
                    )}
                  </select>
                </label>
                {workspace.windows.length === 0 ? <p className="muted">Refresh targets after adding or exposing a window the bridge can resolve.</p> : null}

                <label className="field">
                  <span>Saved Flow Name</span>
                  <input value={recorderFlowName} onChange={(event) => setRecorderFlowName(event.target.value)} />
                </label>

                <div className="button-row">
                  <button className="ghost" onClick={() => void refreshWindows()} type="button">
                    Refresh Targets
                  </button>
                  <button className="primary" disabled={!selectedWindow || isRecording || isRecorderPending} onClick={() => void startRecording()} type="button">
                    Start Recording
                  </button>
                  <button className="ghost" disabled={!isRecording && !isRecorderPending} onClick={() => void stopRecording()} type="button">
                    Stop
                  </button>
                  <button className="primary" disabled={recordedSteps.length === 0 || isRecording || isRecorderPending} onClick={() => void saveRecording()} type="button">
                    Save Recording
                  </button>
                </div>

                <div className="status-stack">
                  <KeyValue label="Status" value={recorderStatus} />
                  <KeyValue label="Selected Window" value={selectedWindow?.title ?? "None"} />
                  <KeyValue label="Captured Steps" value={`${recordedSteps.length}`} />
                </div>
              </article>
            </div>

            <article className="panel">
              <div className="panel-header">
                <div>
                  <p>Captured Actions</p>
                  <h2>{recordedSteps.length === 0 ? "No Recorded Steps Yet" : "Recorder Queue"}</h2>
                </div>
              </div>

              {recordedSteps.length === 0 ? (
                <p className="muted">Start recording, interact with the target app, then stop to review the captured clicks, drags, scrolls, and key steps.</p>
              ) : (
                <div className="step-list">
                  {recordedSteps.map((step) => (
                    <div className="step-card" key={step.id}>
                      <div>
                        <strong>{formatStepType(step.type)}</strong>
                        <span>{stepDetail(step, workspace.anchors)}</span>
                      </div>
                      <small>Step {step.ordinal + 1}</small>
                    </div>
                  ))}
                </div>
              )}
            </article>
          </section>
        )}

        {selectedSection === "editor" && (
          <section className="page">
            <Header
              eyebrow="Authoring"
              title="Flow Editor"
              subtitle="Adjust targeting, timing, and action parameters without touching the raw JSON files."
              meta={editorDraft ? `${enabledEditorStepCount}/${editorDraft.steps.length} active steps` : "Draft not selected"}
            />

            <div className="editor-toolbar">
              <div className="editor-toolbar-copy">
                <strong>{editorDraft?.name ?? "No flow selected"}</strong>
                <span>{editorStatus}</span>
              </div>
              <div className="editor-toolbar-meta">
                <span className="badge">{editorDraft?.steps.length ?? 0} steps</span>
                <span className={hasUnsavedEditorWork ? "toolbar-status dirty" : "toolbar-status"}>
                  {hasUnsavedEditorWork ? "Unsaved changes" : "All changes saved"}
                </span>
              </div>
              <div className="button-row">
                <button
                  className="ghost"
                  onClick={() => {
                    if (!confirmReplaceEditorDraft()) {
                      return;
                    }

                    const flow = createFlow();
                    setSelectedFlowId(flow.id);
                    hydrateEditor(flow);
                  }}
                  type="button"
                >
                  New Flow
                </button>
                <button
                  className="ghost"
                  disabled={!selectedFlow}
                  onClick={() => {
                    if (!selectedFlow) {
                      return;
                    }

                    if (!confirmReplaceEditorDraft()) {
                      return;
                    }

                    const copy = cloneFlow(selectedFlow) as Flow;
                    copy.id = createId();
                    copy.name = `${selectedFlow.name} Copy`;
                    copy.createdAt = new Date().toISOString();
                    copy.updatedAt = copy.createdAt;
                    copy.version = 1;
                    copy.steps = copy.steps.map((step) => ({ ...step, id: createId() }));
                    setSelectedFlowId(copy.id);
                    hydrateEditor(copy);
                  }}
                  type="button"
                >
                  Duplicate
                </button>
                <button className="ghost" disabled={!editorDraft || !editorIsDirty} onClick={() => hydrateEditor(selectedFlow)} type="button">
                  Revert
                </button>
                <button className="primary" disabled={!canSaveEditorDraft} onClick={() => void saveEditorDraft()} type="button">
                  Save
                </button>
                <button className="danger" disabled={!editorDraft || !selectedFlowStepIds.size} onClick={() => void deleteSelectedFlow()} type="button">
                  Delete
                </button>
              </div>
            </div>

            {editorDraft ? (
              <div className="editor-layout">
                <article className="panel editor-sidebar-panel">
                  <div className="panel-header">
                    <div>
                      <p>Flow</p>
                      <h2>Metadata</h2>
                    </div>
                    <span className="badge muted-badge">v{editorDraft.version}</span>
                  </div>

                  <div className="panel-section">
                    <label className="field">
                      <span>Flow Name</span>
                      <input
                        value={editorDraft.name}
                        onChange={(event) =>
                          mutateEditorDraft((draft) => {
                            draft.name = event.target.value;
                            return draft;
                          })
                        }
                      />
                    </label>
                    <label className="field">
                      <span>Description</span>
                      <input
                        value={editorDraft.description}
                        onChange={(event) =>
                          mutateEditorDraft((draft) => {
                            draft.description = event.target.value;
                            return draft;
                          })
                        }
                      />
                    </label>
                    <label className="field">
                      <span>Default Timeout</span>
                      <input
                        type="number"
                        value={editorDraft.defaultTimeoutMs}
                        onChange={(event) =>
                          mutateEditorDraft((draft) => {
                            draft.defaultTimeoutMs = Math.max(0, Number(event.target.value) || 0);
                            return draft;
                          })
                        }
                      />
                    </label>
                  </div>

                  <div className="panel-header compact">
                    <div>
                      <p>Targeting</p>
                      <h2>Window Hints</h2>
                    </div>
                  </div>

                  <div className="panel-section">
                    <label className="field">
                      <span>Bundle ID</span>
                      <input
                        value={editorDraft.targetHint.bundleID ?? ""}
                        onChange={(event) =>
                          mutateEditorDraft((draft) => {
                            draft.targetHint.bundleID = normalizeOptional(event.target.value);
                            return draft;
                          })
                        }
                      />
                    </label>
                    <label className="field">
                      <span>App Name</span>
                      <input
                        value={editorDraft.targetHint.appName ?? ""}
                        onChange={(event) =>
                          mutateEditorDraft((draft) => {
                            draft.targetHint.appName = normalizeOptional(event.target.value);
                            return draft;
                          })
                        }
                      />
                    </label>
                    <label className="field">
                      <span>Window Title Contains</span>
                      <input
                        value={editorDraft.targetHint.windowTitleContains ?? ""}
                        onChange={(event) =>
                          mutateEditorDraft((draft) => {
                            draft.targetHint.windowTitleContains = normalizeOptional(event.target.value);
                            return draft;
                          })
                        }
                      />
                    </label>
                  </div>

                  <div className="panel-header compact">
                    <div>
                      <p>Summary</p>
                      <h2>Draft Health</h2>
                    </div>
                  </div>

                  <div className="status-stack">
                    <KeyValue label="Created" value={fmtDate(editorDraft.createdAt)} />
                    <KeyValue label="Updated" value={fmtDate(editorDraft.updatedAt)} />
                    <KeyValue label="Enabled Steps" value={`${enabledEditorStepCount}`} />
                  </div>

                  <div className="panel-header compact">
                    <div>
                      <p>Preview</p>
                      <h2>Click Map</h2>
                    </div>
                  </div>

                  <PreviewSurface flow={editorDraft} />
                </article>

                <article className="panel editor-sequence-panel">
                  <div className="panel-header">
                    <div>
                      <p>Sequence</p>
                      <h2>Step Timeline</h2>
                    </div>
                    <span className="badge">{editorDraft.steps.length} total</span>
                  </div>

                  <div className="key-grid compact-grid">
                    <KeyValue label="Active" value={`${enabledEditorStepCount}`} />
                    <KeyValue label="Anchors" value={`${workspace.anchors.length}`} />
                    <KeyValue label="Timeout" value={`${editorDraft.defaultTimeoutMs} ms`} />
                  </div>

                  <div className="panel-header compact">
                    <div>
                      <p>Add Step</p>
                      <h2>Common Actions</h2>
                    </div>
                  </div>

                  <div className="step-type-grid">
                    {stepTypes.map((type) => (
                      <button className="ghost small add-step-button" key={type} onClick={() => addAction(type)} type="button">
                        <strong>{formatStepType(type)}</strong>
                        <span>{stepPaletteSummary(type)}</span>
                      </button>
                    ))}
                  </div>

                  <div className="step-list editor-step-list">
                    {editorDraft.steps.map((step) => (
                      <button
                        className={selectedEditorStep?.id === step.id ? "step-card active timeline-step" : "step-card timeline-step"}
                        key={step.id}
                        onClick={() => setSelectedEditorStepId(step.id)}
                        type="button"
                      >
                        <div className="step-index">{step.ordinal + 1}</div>
                        <div className="step-copy">
                          <div className="step-title-row">
                            <strong>{formatStepType(step.type)}</strong>
                            {!step.enabled ? <span className="inline-badge">Disabled</span> : null}
                            {step.timeoutMs ? <span className="inline-badge">{step.timeoutMs} ms</span> : null}
                          </div>
                          <span>{stepDetail(step, workspace.anchors)}</span>
                        </div>
                      </button>
                    ))}
                  </div>
                </article>

                <article className="panel inspector">
                  <div className="panel-header">
                    <div>
                      <p>Inspector</p>
                      <h2>{selectedEditorStep ? formatStepType(selectedEditorStep.type) : "Select a step"}</h2>
                    </div>
                    {selectedEditorStepOrdinal ? <span className="badge muted-badge">Step {selectedEditorStepOrdinal}</span> : null}
                  </div>

                  {selectedEditorStep ? (
                    <>
                      <div className="panel-section">
                        <div className="field-grid compact-fields">
                          <label className="field">
                            <span>Type</span>
                            <select value={selectedEditorStep.type} onChange={(event) => replaceSelectedStepType(event.target.value as StepType)}>
                              {stepTypes.map((type) => (
                                <option key={type} value={type}>
                                  {formatStepType(type)}
                                </option>
                              ))}
                            </select>
                          </label>
                          <label className="field checkbox-field">
                            <span>Enabled</span>
                            <input
                              checked={selectedEditorStep.enabled}
                              onChange={(event) => upsertSelectedStep((step) => void (step.enabled = event.target.checked))}
                              type="checkbox"
                            />
                          </label>
                          <label className="field">
                            <span>Timeout Override</span>
                            <input
                              type="number"
                              value={selectedEditorStep.timeoutMs ?? ""}
                              onChange={(event) =>
                                upsertSelectedStep((step) => {
                                  step.timeoutMs = event.target.value === "" ? undefined : Math.max(0, Number(event.target.value) || 0);
                                })
                              }
                            />
                          </label>
                          <label className="field">
                            <span>Retry Attempts</span>
                            <input
                              type="number"
                              value={selectedEditorStep.retryPolicy?.maxAttempts ?? 1}
                              onChange={(event) =>
                                upsertSelectedStep((step) => {
                                  step.retryPolicy = {
                                    maxAttempts: Math.max(1, Number(event.target.value) || 1),
                                    backoffMs: step.retryPolicy?.backoffMs ?? 0
                                  };
                                })
                              }
                            />
                          </label>
                          <label className="field">
                            <span>Retry Backoff</span>
                            <input
                              type="number"
                              value={selectedEditorStep.retryPolicy?.backoffMs ?? 0}
                              onChange={(event) =>
                                upsertSelectedStep((step) => {
                                  step.retryPolicy = {
                                    maxAttempts: step.retryPolicy?.maxAttempts ?? 1,
                                    backoffMs: Math.max(0, Number(event.target.value) || 0)
                                  };
                                })
                              }
                            />
                          </label>
                          <label className="field">
                            <span>Debug Note</span>
                            <input
                              value={selectedEditorStep.debugNote ?? ""}
                              onChange={(event) =>
                                upsertSelectedStep((step) => {
                                  step.debugNote = normalizeOptional(event.target.value);
                                })
                              }
                            />
                          </label>
                        </div>
                      </div>

                      <div className="panel-header compact">
                        <div>
                          <p>Parameters</p>
                          <h2>Step Settings</h2>
                        </div>
                      </div>

                      <div className="panel-section">
                        {selectedEditorStep.type === "wait" && (
                          <label className="field">
                            <span>Duration (ms)</span>
                            <input
                              type="number"
                              value={selectedEditorStep.params.durationMs ?? 500}
                              onChange={(event) =>
                                upsertSelectedStep((step) => {
                                  step.params.durationMs = Math.max(0, Number(event.target.value) || 0);
                                })
                              }
                            />
                          </label>
                        )}

                        {selectedEditorStep.type === "waitForAnchor" && (
                          <div className="field-grid compact-fields">
                            <label className="field">
                              <span>Anchor</span>
                              <select
                                value={selectedEditorStep.params.anchorID ?? ""}
                                onChange={(event) =>
                                  upsertSelectedStep((step) => {
                                    step.params.anchorID = normalizeOptional(event.target.value);
                                  })
                                }
                              >
                                <option value="">None</option>
                                {workspace.anchors.map((anchor) => (
                                  <option key={anchor.id} value={anchor.id}>
                                    {anchor.name}
                                  </option>
                                ))}
                              </select>
                            </label>
                            <label className="field">
                              <span>Poll Interval (ms)</span>
                              <input
                                type="number"
                                value={selectedEditorStep.params.pollIntervalMs ?? 120}
                                onChange={(event) =>
                                  upsertSelectedStep((step) => {
                                    step.params.pollIntervalMs = Math.max(1, Number(event.target.value) || 120);
                                  })
                                }
                              />
                            </label>
                          </div>
                        )}

                        {selectedEditorStep.type === "clickAt" && (
                          <div className="field-grid compact-fields">
                            <label className="field">
                              <span>X</span>
                              <input
                                max="1"
                                min="0"
                                step="0.001"
                                type="number"
                                value={selectedEditorStep.params.point?.x ?? 0.5}
                                onChange={(event) =>
                                  upsertSelectedStep((step) => {
                                    step.params.point = {
                                      x: Math.max(0, Math.min(1, Number(event.target.value) || 0)),
                                      y: step.params.point?.y ?? 0.5
                                    };
                                  })
                                }
                              />
                            </label>
                            <label className="field">
                              <span>Y</span>
                              <input
                                max="1"
                                min="0"
                                step="0.001"
                                type="number"
                                value={selectedEditorStep.params.point?.y ?? 0.5}
                                onChange={(event) =>
                                  upsertSelectedStep((step) => {
                                    step.params.point = {
                                      x: step.params.point?.x ?? 0.5,
                                      y: Math.max(0, Math.min(1, Number(event.target.value) || 0))
                                    };
                                  })
                                }
                              />
                            </label>
                            <label className="field">
                              <span>Button</span>
                              <select
                                value={selectedEditorStep.params.button ?? "left"}
                                onChange={(event) =>
                                  upsertSelectedStep((step) => {
                                    step.params.button = event.target.value as MouseButton;
                                  })
                                }
                              >
                                {mouseButtons.map((button) => (
                                  <option key={button} value={button}>
                                    {button}
                                  </option>
                                ))}
                              </select>
                            </label>
                          </div>
                        )}

                        {selectedEditorStep.type === "scrollAt" && (
                          <div className="field-grid compact-fields">
                            <label className="field">
                              <span>X</span>
                              <input
                                max="1"
                                min="0"
                                step="0.001"
                                type="number"
                                value={selectedEditorStep.params.point?.x ?? 0.5}
                                onChange={(event) =>
                                  upsertSelectedStep((step) => {
                                    step.params.point = {
                                      x: Math.max(0, Math.min(1, Number(event.target.value) || 0)),
                                      y: step.params.point?.y ?? 0.5
                                    };
                                  })
                                }
                              />
                            </label>
                            <label className="field">
                              <span>Y</span>
                              <input
                                max="1"
                                min="0"
                                step="0.001"
                                type="number"
                                value={selectedEditorStep.params.point?.y ?? 0.5}
                                onChange={(event) =>
                                  upsertSelectedStep((step) => {
                                    step.params.point = {
                                      x: step.params.point?.x ?? 0.5,
                                      y: Math.max(0, Math.min(1, Number(event.target.value) || 0))
                                    };
                                  })
                                }
                              />
                            </label>
                            <label className="field">
                              <span>Delta X</span>
                              <input
                                type="number"
                                value={selectedEditorStep.params.deltaX ?? 0}
                                onChange={(event) =>
                                  upsertSelectedStep((step) => {
                                    step.params.deltaX = Math.trunc(Number(event.target.value) || 0);
                                  })
                                }
                              />
                            </label>
                            <label className="field">
                              <span>Delta Y</span>
                              <input
                                type="number"
                                value={selectedEditorStep.params.deltaY ?? 0}
                                onChange={(event) =>
                                  upsertSelectedStep((step) => {
                                    step.params.deltaY = Math.trunc(Number(event.target.value) || 0);
                                  })
                                }
                              />
                            </label>
                          </div>
                        )}

                        {selectedEditorStep.type === "dragTo" && (
                          <div className="field-grid compact-fields">
                            <label className="field">
                              <span>Start X</span>
                              <input
                                max="1"
                                min="0"
                                step="0.001"
                                type="number"
                                value={selectedEditorStep.params.point?.x ?? 0.35}
                                onChange={(event) =>
                                  upsertSelectedStep((step) => {
                                    step.params.point = {
                                      x: Math.max(0, Math.min(1, Number(event.target.value) || 0)),
                                      y: step.params.point?.y ?? 0.5
                                    };
                                  })
                                }
                              />
                            </label>
                            <label className="field">
                              <span>Start Y</span>
                              <input
                                max="1"
                                min="0"
                                step="0.001"
                                type="number"
                                value={selectedEditorStep.params.point?.y ?? 0.5}
                                onChange={(event) =>
                                  upsertSelectedStep((step) => {
                                    step.params.point = {
                                      x: step.params.point?.x ?? 0.35,
                                      y: Math.max(0, Math.min(1, Number(event.target.value) || 0))
                                    };
                                  })
                                }
                              />
                            </label>
                            <label className="field">
                              <span>End X</span>
                              <input
                                max="1"
                                min="0"
                                step="0.001"
                                type="number"
                                value={selectedEditorStep.params.endPoint?.x ?? 0.7}
                                onChange={(event) =>
                                  upsertSelectedStep((step) => {
                                    step.params.endPoint = {
                                      x: Math.max(0, Math.min(1, Number(event.target.value) || 0)),
                                      y: step.params.endPoint?.y ?? 0.5
                                    };
                                  })
                                }
                              />
                            </label>
                            <label className="field">
                              <span>End Y</span>
                              <input
                                max="1"
                                min="0"
                                step="0.001"
                                type="number"
                                value={selectedEditorStep.params.endPoint?.y ?? 0.5}
                                onChange={(event) =>
                                  upsertSelectedStep((step) => {
                                    step.params.endPoint = {
                                      x: step.params.endPoint?.x ?? 0.7,
                                      y: Math.max(0, Math.min(1, Number(event.target.value) || 0))
                                    };
                                  })
                                }
                              />
                            </label>
                            <label className="field">
                              <span>Button</span>
                              <select
                                value={selectedEditorStep.params.button ?? "left"}
                                onChange={(event) =>
                                  upsertSelectedStep((step) => {
                                    step.params.button = event.target.value as MouseButton;
                                  })
                                }
                              >
                                {mouseButtons.map((button) => (
                                  <option key={button} value={button}>
                                    {button}
                                  </option>
                                ))}
                              </select>
                            </label>
                            <label className="field">
                              <span>Duration (ms)</span>
                              <input
                                type="number"
                                value={selectedEditorStep.params.durationMs ?? 350}
                                onChange={(event) =>
                                  upsertSelectedStep((step) => {
                                    step.params.durationMs = Math.max(0, Number(event.target.value) || 0);
                                  })
                                }
                              />
                            </label>
                          </div>
                        )}

                        {selectedEditorStep.type === "pressKey" && (
                          <div className="field-grid compact-fields">
                            <label className="field">
                              <span>Key Code</span>
                              <input
                                value={selectedEditorStep.params.keyCode ?? ""}
                                onChange={(event) =>
                                  upsertSelectedStep((step) => {
                                    step.params.keyCode = event.target.value.trim().toUpperCase();
                                  })
                                }
                              />
                            </label>
                            <div className="modifier-row">
                              {["command", "shift", "control", "option"].map((modifier) => (
                                <button
                                  className={selectedEditorStep.params.modifiers.includes(modifier) ? "toggle active" : "toggle"}
                                  key={modifier}
                                  onClick={() => toggleModifier(modifier)}
                                  type="button"
                                >
                                  {modifier}
                                </button>
                              ))}
                            </div>
                          </div>
                        )}

                        {selectedEditorStep.type === "checkpointScreenshot" && (
                          <label className="field">
                            <span>Label</span>
                            <input
                              value={selectedEditorStep.params.label ?? ""}
                              onChange={(event) =>
                                upsertSelectedStep((step) => {
                                  step.params.label = normalizeOptional(event.target.value);
                                })
                              }
                            />
                          </label>
                        )}

                        {(selectedEditorStep.type === "attachWindow" || selectedEditorStep.type === "focusWindow") && (
                          <p className="muted">This action has no editable parameters.</p>
                        )}
                      </div>

                      <div className="inspector-actions">
                        <button className="ghost" onClick={() => moveStep(selectedEditorStep.id, -1)} type="button">
                          Move Up
                        </button>
                        <button className="ghost" onClick={() => moveStep(selectedEditorStep.id, 1)} type="button">
                          Move Down
                        </button>
                        <button className="ghost" onClick={() => duplicateStep(selectedEditorStep.id)} type="button">
                          Duplicate
                        </button>
                        <button className="danger" onClick={() => removeStep(selectedEditorStep.id)} type="button">
                          Delete
                        </button>
                      </div>
                    </>
                  ) : (
                    <p className="muted">Select a step from the timeline to inspect it.</p>
                  )}
                </article>
              </div>
            ) : (
              <article className="panel">
                <p className="muted">Create or select a flow to edit.</p>
              </article>
            )}
          </section>
        )}

        {selectedSection === "runner" && (
          <section className="page">
            <Header
              eyebrow="Playback"
              title="Runner"
              subtitle="Replay the selected flow and inspect step-level results from the Electron shell."
              meta={runnerCompletion}
            />

            <div className="button-row">
              <button className="primary" disabled={!selectedFlow || isRunningFlow} onClick={() => void runSelectedFlow()} type="button">
                Run Selected Flow
              </button>
              <button className="ghost" disabled={!selectedFlow || !isRunningFlow} onClick={() => void abortRunningFlow()} type="button">
                Abort
              </button>
            </div>

            <div className="panel-grid two-up">
              <article className="panel">
                <div className="panel-header">
                  <div>
                    <p>Status</p>
                    <h2>{runnerStatus}</h2>
                  </div>
                </div>
                <div className="key-grid">
                  <KeyValue label="Flow" value={selectedFlow?.name ?? "None"} />
                  <KeyValue label="Steps" value={`${selectedFlow?.steps.length ?? 0}`} />
                  <KeyValue label="Last Status" value={lastRunReport?.status ?? "idle"} />
                </div>

                {lastRunReport ? (
                  <div className="run-summary">
                    <KeyValue label="Started" value={fmtDate(lastRunReport.startedAt)} />
                    <KeyValue label="Finished" value={fmtDate(lastRunReport.finishedAt)} />
                    <KeyValue label="Reason" value={lastRunReport.stopReason ?? "Completed"} />
                  </div>
                ) : null}
              </article>

              <article className="panel">
                <div className="panel-header">
                  <div>
                    <p>Flow Steps</p>
                    <h2>Current Sequence</h2>
                  </div>
                </div>
                {selectedFlow ? (
                  <div className="step-list">
                    {selectedFlow.steps.map((step) => (
                      <div className="step-card" key={step.id}>
                        <div>
                          <strong>{formatStepType(step.type)}</strong>
                          <span>{stepDetail(step, workspace.anchors)}</span>
                        </div>
                        <small>Step {step.ordinal + 1}</small>
                      </div>
                    ))}
                  </div>
                ) : (
                  <p className="muted">No runnable flow selected.</p>
                )}
              </article>
            </div>

            <article className="panel">
              <div className="panel-header">
                <div>
                  <p>Step Results</p>
                  <h2>Last Run</h2>
                </div>
              </div>
              {lastRunReport ? (
                <div className="step-list">
                  {lastRunReport.stepResults.map((result) => (
                    <div className={`step-card ${result.status}`} key={result.stepID}>
                      <div>
                        <strong>{result.status}</strong>
                        <span>{result.reason ?? "Completed"}</span>
                      </div>
                      <small>{fmtDate(result.finishedAt)}</small>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="muted">Run a flow to inspect step-level results.</p>
              )}
            </article>
          </section>
        )}

        {selectedSection === "permissions" && (
          <section className="page">
            <Header
              eyebrow="System"
              title="Permissions"
              subtitle="The Electron shell now asks the Swift bridge for real macOS permission state before recording or playback."
              meta={allPermissionsGranted ? undefined : `${grantedPermissionCount}/3 granted`}
            />

            <div className={`panel-grid${allPermissionsGranted ? " single" : " two-up"}`}>
              {!allPermissionsGranted ? (
                <article className="panel">
                  <div className="panel-header">
                    <div>
                      <p>Required</p>
                      <h2>Native Automation Access</h2>
                    </div>
                  </div>
                  <div className="status-stack">
                    <KeyValue label="Accessibility" value={permissionLabel(permissions.accessibility)} />
                    <KeyValue label="Input Monitoring" value={permissionLabel(permissions.inputMonitoring)} />
                    <KeyValue label="Screen Recording" value={permissionLabel(permissions.screenRecording)} />
                  </div>
                </article>
              ) : null}

              <article className="panel">
                <div className="panel-header">
                  <div>
                    <p>Current State</p>
                    <h2>Port Boundaries</h2>
                  </div>
                </div>
                <ul className="plain-list">
                  <li>The Electron shell edits and saves flows and anchors against the same workspace JSON.</li>
                  <li>Window discovery, recording, and non-vision playback now execute through the Swift bridge.</li>
                  <li>Anchor-based screen matching still needs a real frame provider and matcher.</li>
                </ul>
              </article>
            </div>
          </section>
        )}
      </main>
    </div>
  );
}
