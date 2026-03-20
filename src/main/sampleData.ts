import { randomUUID } from "node:crypto";
import type { Anchor, Flow, FlowStep } from "../shared/models";

export const sampleAnchor: Anchor = {
  id: "22222222-2222-2222-2222-222222222222",
  assetID: "11111111-1111-1111-1111-111111111111",
  name: "inventory_open",
  region: {
    x: 0.72,
    y: 0.08,
    width: 0.2,
    height: 0.25
  },
  threshold: 0.93,
  matchMode: "grayscaleTemplate",
  notes: "Top-right inventory panel for the practice target."
};

const makeStep = (type: FlowStep["type"], ordinal: number, params: Partial<FlowStep["params"]> = {}): FlowStep => ({
  id: randomUUID(),
  ordinal,
  type,
  params: {
    ...params,
    modifiers: params.modifiers ?? []
  },
  enabled: true,
  preconditions: [],
  postconditions: []
});

export const sampleFlow = (): Flow => {
  const timestamp = new Date().toISOString();

  return {
    id: "33333333-3333-3333-3333-333333333333",
    name: "Practice Window Loop",
    description:
      "A starter flow for the first implementation spike: attach, wait on a visual anchor, click a point, press a key, and store a checkpoint.",
    targetHint: {
      bundleID: "com.example.GameLauncher",
      appName: "Practice Java Window",
      windowTitleContains: "Practice Arena"
    },
    defaultTimeoutMs: 5000,
    createdAt: timestamp,
    updatedAt: timestamp,
    version: 1,
    steps: [
      makeStep("attachWindow", 0),
      makeStep("focusWindow", 1),
      {
        ...makeStep("waitForAnchor", 2, {
          anchorID: sampleAnchor.id,
          pollIntervalMs: 120
        }),
        timeoutMs: 5000
      },
      makeStep("clickAt", 3, {
        button: "left",
        point: {
          x: 0.64,
          y: 0.38
        }
      }),
      makeStep("pressKey", 4, {
        keyCode: "SPACE"
      }),
      makeStep("checkpointScreenshot", 5, {
        label: "after_action"
      })
    ]
  };
};
