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

type AppSection = "overview" | "recorder" | "editor" | "runner" | "permissions";

const sections: Array<{ id: AppSection; label: string; eyebrow: string }> = [
  { id: "overview", label: "Overview", eyebrow: "Workspace" },
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

const PreviewSurface = ({ flow }: { flow: Flow }) => (
  <div className="preview-surface">
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
);

const Header = ({ title, subtitle }: { title: string; subtitle: string }) => (
  <header className="section-header">
    <p>{title}</p>
    <div>
      <h1>{title}</h1>
      <span>{subtitle}</span>
    </div>
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
  const [selectedSection, setSelectedSection] = useState<AppSection>("overview");
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
    setEditorStatus(`Saved '${flowToSave.name}'.`);
  };

  const deleteSelectedFlow = async () => {
    if (!selectedFlow) {
      return;
    }

    const payload = await window.desktopflow.deleteFlow(selectedFlow.id);
    setWorkspace(payload);
    const nextFlow = payload.flows[0] ?? null;
    setSelectedFlowId(nextFlow?.id ?? null);
    hydrateEditor(nextFlow);
    setEditorStatus(nextFlow ? `Editing '${nextFlow.name}'.` : "Create or select a flow to edit.");
  };

  const refreshWindows = async () => {
    const payload = await window.desktopflow.loadWorkspace();
    setWorkspace(payload);
    setSelectedWindowId((current) =>
      current && payload.windows.some((window) => window.id === current) ? current : payload.windows[0]?.id ?? null
    );
    setRecorderStatus(`Loaded ${payload.windows.length} configured target window${payload.windows.length === 1 ? "" : "s"}.`);
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
      setRecorderStatus("Record at least one click or key press before saving.");
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

    const payload = await window.desktopflow.saveFlow(flow);
    setWorkspace(payload);
    setSelectedFlowId(flow.id);
    hydrateEditor(flow);
    setRecordedSteps([]);
    setIsRecording(false);
    setSelectedSection("editor");
    setRecorderStatus(`Saved ${flow.steps.length - 2} recorded steps to '${flow.name}'.`);
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

    const aborted = await window.desktopflow.abortFlow(selectedFlow.id);
    setRunnerStatus(aborted ? "Abort requested." : "No active native run to abort.");
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

  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          <span>Desktopflow</span>
          <strong>Electron Port</strong>
        </div>

        <nav className="nav-card">
          <span className="nav-label">Workspace</span>
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

        <div className="flow-card">
          <div className="flow-card-header">
            <span>Flows</span>
            <strong>{workspace.flows.length}</strong>
          </div>
          <div className="flow-list">
            {workspace.flows.map((flow) => (
              <button
                className={selectedFlow?.id === flow.id ? "flow-item active" : "flow-item"}
                key={flow.id}
                onClick={() => selectFlow(flow.id)}
                type="button"
              >
                <strong>{flow.name}</strong>
                <span>{flow.description}</span>
              </button>
            ))}
          </div>
        </div>
      </aside>

      <main className="content">
        <div className="topbar">
          <div>
            <p>Workspace Root</p>
            <strong>{workspace.workspaceRoot || "Loading..."}</strong>
          </div>
          <div className="status-pill">
            <span>{lastError ? "Issue" : isLoading ? "Loading" : "Ready"}</span>
            <strong>{lastError ?? "Electron shell is active"}</strong>
          </div>
        </div>

        {selectedSection === "overview" && (
          <section className="page">
            <Header
              title="Overview"
              subtitle="JSON-backed flow inventory, selected flow summary, and the current runner state."
            />

            <div className="stats-grid">
              <article className="stat-card">
                <span>Flows</span>
                <strong>{workspace.flows.length}</strong>
              </article>
              <article className="stat-card">
                <span>Anchors</span>
                <strong>{workspace.anchors.length}</strong>
              </article>
              <article className="stat-card">
                <span>Runner</span>
                <strong>{lastRunReport?.status ?? "idle"}</strong>
              </article>
            </div>

            <div className="panel-grid">
              <article className="panel">
                <div className="panel-header">
                  <div>
                    <p>Selected Flow</p>
                    <h2>{selectedFlow?.name ?? "No flow selected"}</h2>
                  </div>
                  {selectedFlow ? <span className="badge">{selectedFlow.steps.length} steps</span> : null}
                </div>

                {selectedFlow ? (
                  <>
                    <p className="muted">{selectedFlow.description}</p>
                    <div className="key-grid">
                      <KeyValue label="Default Timeout" value={`${selectedFlow.defaultTimeoutMs} ms`} />
                      <KeyValue label="Bundle ID" value={selectedFlow.targetHint.bundleID ?? "Unset"} />
                      <KeyValue label="Updated" value={fmtDate(selectedFlow.updatedAt)} />
                    </div>
                    <PreviewSurface flow={selectedFlow} />
                  </>
                ) : (
                  <p className="muted">Select a flow from the sidebar.</p>
                )}
              </article>

              <article className="panel notice-panel">
                <div className="panel-header">
                  <div>
                    <p>Port Notes</p>
                    <h2>What moved over</h2>
                  </div>
                </div>
                <ul className="plain-list">
                  <li>The app now runs in Electron with React and TypeScript.</li>
                  <li>Existing `WorkspaceData/flows` and `WorkspaceData/anchors` JSON files load directly.</li>
                  <li>The Electron shell now calls a Swift bridge for window discovery, live recording, permissions, and native playback.</li>
                </ul>
              </article>
            </div>
          </section>
        )}

        {selectedSection === "recorder" && (
          <section className="page">
            <Header title="Recorder" subtitle="Capture real clicks and keys from the selected macOS window through the Swift bridge." />

            <div className="panel-grid two-up">
              <article className="panel">
                <div className="panel-header">
                  <div>
                    <p>Target</p>
                    <h2>Recording Setup</h2>
                  </div>
                </div>

                <label className="field">
                  <span>Target Window</span>
                  <select value={selectedWindowId ?? ""} onChange={(event) => setSelectedWindowId(event.target.value)}>
                    {workspace.windows.map((window) => (
                      <option key={window.id} value={window.id}>
                        {window.appName} · {window.title}
                      </option>
                    ))}
                  </select>
                </label>

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

              <article className="panel">
                <div className="panel-header">
                  <div>
                    <p>Live Capture</p>
                    <h2>Native Recorder</h2>
                  </div>
                  <span className="badge">Swift bridge</span>
                </div>
                <p className="muted">
                  Recording now uses the original macOS event-monitoring approach from Swift. Input Monitoring is typically required for key capture, and clicks are only recorded when they land inside the selected window.
                </p>
                <div className="status-stack">
                  <KeyValue label="Accessibility" value={permissionLabel(permissions.accessibility)} />
                  <KeyValue label="Input Monitoring" value={permissionLabel(permissions.inputMonitoring)} />
                  <KeyValue label="Screen Recording" value={permissionLabel(permissions.screenRecording)} />
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
                <p className="muted">Start recording, interact with the target app, then stop to review the captured click and key steps.</p>
              ) : (
                <div className="step-list">
                  {recordedSteps.map((step) => (
                    <div className="step-card" key={step.id}>
                      <div>
                        <strong>{step.type}</strong>
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
            <Header title="Flow Editor" subtitle="Adjust targeting, timing, and action parameters without touching the raw JSON files." />

            <div className="editor-toolbar">
              <div className="button-row">
                <button
                  className="ghost"
                  onClick={() => {
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
                <button className="primary" disabled={!editorDraft} onClick={() => void saveEditorDraft()} type="button">
                  Save
                </button>
                <button className="danger" disabled={!editorDraft || !selectedFlowStepIds.size} onClick={() => void deleteSelectedFlow()} type="button">
                  Delete
                </button>
              </div>
              <span className={editorIsDirty ? "toolbar-status dirty" : "toolbar-status"}>{editorStatus}</span>
            </div>

            {editorDraft ? (
              <div className="editor-layout">
                <article className="panel">
                  <div className="panel-header">
                    <div>
                      <p>Flow</p>
                      <h2>Metadata</h2>
                    </div>
                  </div>

                  <div className="field-grid">
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
                      <p>Actions</p>
                      <h2>Step List</h2>
                    </div>
                    <div className="button-row compact">
                      {stepTypes.map((type) => (
                        <button className="ghost small" key={type} onClick={() => addAction(type)} type="button">
                          + {type}
                        </button>
                      ))}
                    </div>
                  </div>

                  <div className="step-list">
                    {editorDraft.steps.map((step) => (
                      <button
                        className={selectedEditorStep?.id === step.id ? "step-card active" : "step-card"}
                        key={step.id}
                        onClick={() => setSelectedEditorStepId(step.id)}
                        type="button"
                      >
                        <div>
                          <strong>{step.type}</strong>
                          <span>{stepDetail(step, workspace.anchors)}</span>
                        </div>
                        <small>Step {step.ordinal + 1}</small>
                      </button>
                    ))}
                  </div>
                </article>

                <article className="panel inspector">
                  <div className="panel-header">
                    <div>
                      <p>Inspector</p>
                      <h2>{selectedEditorStep?.type ?? "Select a step"}</h2>
                    </div>
                  </div>

                  {selectedEditorStep ? (
                    <>
                      <div className="field-grid">
                        <label className="field">
                          <span>Type</span>
                          <select value={selectedEditorStep.type} onChange={(event) => replaceSelectedStepType(event.target.value as StepType)}>
                            {stepTypes.map((type) => (
                              <option key={type} value={type}>
                                {type}
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

                      <div className="panel-header compact">
                        <div>
                          <p>Parameters</p>
                          <h2>Step Settings</h2>
                        </div>
                      </div>

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
                        <div className="field-grid">
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
                        <div className="field-grid">
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

                      {selectedEditorStep.type === "pressKey" && (
                        <div className="field-grid">
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

                      <div className="button-row">
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
                    <p className="muted">Select a step from the list to inspect it.</p>
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
            <Header title="Runner" subtitle="Replay the selected flow and inspect step-level results from the Electron shell." />

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
                          <strong>{step.type}</strong>
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
              title="Permissions"
              subtitle="The Electron shell now asks the Swift bridge for real macOS permission state before recording or playback."
            />

            <div className="panel-grid two-up">
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
