import { createHash } from "node:crypto";
import type { Flow, WindowDescriptor } from "../shared/models";

const makeId = (...parts: Array<string | number | undefined>) =>
  createHash("sha1")
    .update(parts.filter(Boolean).join("::"))
    .digest("hex")
    .slice(0, 12);

export const buildWindowCatalog = (flows: Flow[]): WindowDescriptor[] => {
  const windows = new Map<string, WindowDescriptor>();

  for (const flow of flows) {
    const appName = flow.targetHint.appName ?? "Configured Target";
    const title = flow.targetHint.windowTitleContains ?? flow.name;
    const descriptor: WindowDescriptor = {
      id: makeId(flow.targetHint.bundleID, appName, title, flow.targetHint.ownerPID),
      bundleID: flow.targetHint.bundleID,
      appName,
      title,
      ownerPID: flow.targetHint.ownerPID
    };
    windows.set(descriptor.id, descriptor);
  }

  if (windows.size === 0) {
    const fallback: WindowDescriptor = {
      id: makeId("desktopflow-simulated-window"),
      appName: "Desktopflow",
      title: "Simulated Target Window"
    };
    windows.set(fallback.id, fallback);
  }

  return [...windows.values()].sort((left, right) => {
    if (left.appName === right.appName) {
      return left.title.localeCompare(right.title);
    }

    return left.appName.localeCompare(right.appName);
  });
};
