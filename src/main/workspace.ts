import { mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import type { Anchor, Flow, WorkspacePayload } from "../shared/models";
import { sampleAnchor, sampleFlow } from "./sampleData";
import { buildWindowCatalog } from "./windowCatalog";

const jsonExtension = ".json";

const sortObjectKeys = (value: unknown): unknown => {
  if (Array.isArray(value)) {
    return value.map(sortObjectKeys);
  }

  if (value && typeof value === "object") {
    return Object.keys(value as Record<string, unknown>)
      .sort((left, right) => left.localeCompare(right))
      .reduce<Record<string, unknown>>((result, key) => {
        result[key] = sortObjectKeys((value as Record<string, unknown>)[key]);
        return result;
      }, {});
  }

  return value;
};

const prettyJson = (value: unknown) => `${JSON.stringify(sortObjectKeys(value), null, 2)}\n`;

export const getWorkspaceRoot = (): string =>
  path.resolve(process.env.DESKTOPFLOW_WORKSPACE_ROOT ?? process.cwd(), "WorkspaceData");

const flowsDirectory = () => path.join(getWorkspaceRoot(), "flows");
const anchorsDirectory = () => path.join(getWorkspaceRoot(), "anchors");

const readJsonDirectory = async <T>(directory: string): Promise<T[]> => {
  await mkdir(directory, { recursive: true });
  const entries = await readdir(directory, { withFileTypes: true });
  const files = entries.filter((entry) => entry.isFile() && entry.name.endsWith(jsonExtension));

  const values = await Promise.all(
    files.map(async (entry) => {
      const filePath = path.join(directory, entry.name);
      const content = await readFile(filePath, "utf8");
      return JSON.parse(content) as T;
    })
  );

  return values;
};

const writeJsonFile = async (filePath: string, value: unknown) => {
  await writeFile(filePath, prettyJson(value), "utf8");
};

export const ensureSeedData = async () => {
  await mkdir(flowsDirectory(), { recursive: true });
  await mkdir(anchorsDirectory(), { recursive: true });

  const [flowEntries, anchorEntries] = await Promise.all([
    readdir(flowsDirectory()),
    readdir(anchorsDirectory())
  ]);

  if (flowEntries.filter((name) => name.endsWith(jsonExtension)).length === 0) {
    await saveFlow(sampleFlow());
  }

  if (anchorEntries.filter((name) => name.endsWith(jsonExtension)).length === 0) {
    await saveAnchor(sampleAnchor);
  }
};

export const listFlows = async (): Promise<Flow[]> => {
  const flows = await readJsonDirectory<Flow>(flowsDirectory());

  return flows
    .map((flow) => ({
      ...flow,
      steps: [...flow.steps].sort((left, right) => left.ordinal - right.ordinal)
    }))
    .sort((left, right) => right.updatedAt.localeCompare(left.updatedAt));
};

export const listAnchors = async (): Promise<Anchor[]> => readJsonDirectory<Anchor>(anchorsDirectory());

export const saveFlow = async (flow: Flow) => {
  await mkdir(flowsDirectory(), { recursive: true });
  await writeJsonFile(path.join(flowsDirectory(), `${flow.id}${jsonExtension}`), flow);
};

export const saveAnchor = async (anchor: Anchor) => {
  await mkdir(anchorsDirectory(), { recursive: true });
  await writeJsonFile(path.join(anchorsDirectory(), `${anchor.id}${jsonExtension}`), anchor);
};

export const deleteFlow = async (id: string) => {
  await rm(path.join(flowsDirectory(), `${id}${jsonExtension}`), {
    force: true
  });
};

export const loadWorkspace = async (): Promise<WorkspacePayload> => {
  await ensureSeedData();
  const [flows, anchors] = await Promise.all([listFlows(), listAnchors()]);

  return {
    flows,
    anchors,
    windows: buildWindowCatalog(flows),
    workspaceRoot: getWorkspaceRoot()
  };
};
