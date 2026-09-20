import { fingerprint } from "./json.mjs";

export const allowedOperations = Object.freeze({
  github: new Set([
    "add-blocker",
    "add-label",
    "assign-issue",
    "close-issue",
    "comment",
    "create-issue",
    "create-sub-issue",
    "enable-auto-merge",
    "ensure-label",
    "merge-pull-request",
    "open-pull-request",
    "remove-label",
    "update-issue",
  ]),
  git: new Set(["create-branch", "delete-branch", "fetch", "push-branch"]),
  worktree: new Set(["create", "remove"]),
  filesystem: new Set(["write-file", "remove-file"]),
});

function plainObject(value) {
  return value && typeof value === "object" && !Array.isArray(value);
}

export function validateAction(action, index = 0) {
  if (!plainObject(action)) throw new Error(`action ${index + 1} must be an object`);
  const keys = Object.keys(action).sort();
  const expected = ["adapter", "id", "operation", "parameters"];
  if (keys.join(",") !== expected.join(",")) {
    throw new Error(`action ${index + 1} must contain only id, adapter, operation, and parameters`);
  }
  if (typeof action.id !== "string" || !action.id) {
    throw new Error(`action ${index + 1} needs a non-empty id`);
  }
  const operations = allowedOperations[action.adapter];
  if (!operations) throw new Error(`action '${action.id}' uses unknown adapter '${action.adapter}'`);
  if (!operations.has(action.operation)) {
    throw new Error(`action '${action.id}' uses unsupported ${action.adapter} operation '${action.operation}'`);
  }
  if (!plainObject(action.parameters)) {
    throw new Error(`action '${action.id}' parameters must be an object`);
  }
  for (const forbidden of ["command", "script", "shell", "shellCommand"]) {
    if (Object.hasOwn(action.parameters, forbidden)) {
      throw new Error(`action '${action.id}' cannot contain '${forbidden}'`);
    }
  }
  return structuredClone(action);
}

export function createPlan(state, request) {
  if (state.schemaVersion !== 1 || !state.freshness?.fingerprint) {
    throw new Error("planning needs a version 1 workflow state with freshness evidence");
  }
  if (request.schemaVersion !== 1) {
    throw new Error(`unsupported plan request schemaVersion '${request.schemaVersion}'`);
  }
  if (typeof request.operation !== "string" || !request.operation) {
    throw new Error("plan request needs an operation");
  }
  if (!Array.isArray(request.actions) || request.actions.length === 0) {
    throw new Error("plan request needs at least one action");
  }

  const actions = request.actions.map(validateAction);
  const ids = new Set();
  for (const action of actions) {
    if (ids.has(action.id)) throw new Error(`plan repeats action id '${action.id}'`);
    ids.add(action.id);
  }
  const content = {
    schemaVersion: 1,
    operation: request.operation,
    evidence: { stateFingerprint: state.freshness.fingerprint },
    actions,
  };
  return { ...content, planId: fingerprint(content) };
}

export function assertFreshPlan(plan, currentState) {
  if (plan.schemaVersion !== 1) {
    throw new Error(`unsupported plan schemaVersion '${plan.schemaVersion}'`);
  }
  if (fingerprint({
    schemaVersion: plan.schemaVersion,
    operation: plan.operation,
    evidence: plan.evidence,
    actions: plan.actions,
  }) !== plan.planId) {
    throw new Error("plan content does not match its planId");
  }
  if (plan.evidence?.stateFingerprint !== currentState.freshness?.fingerprint) {
    throw new Error("plan is stale; inspect and plan again before apply");
  }
}

export async function applyPlan({ plan, loadCurrentState, adapters }) {
  if (typeof loadCurrentState !== "function") {
    throw new Error("apply needs a live state loader");
  }
  const currentState = await loadCurrentState();
  assertFreshPlan(plan, currentState);
  const receipts = [];

  for (const [index, rawAction] of plan.actions.entries()) {
    const action = validateAction(rawAction, index);
    const adapter = adapters[action.adapter];
    if (!adapter?.execute) throw new Error(`no apply adapter for '${action.adapter}'`);
    const result = await adapter.execute(action.operation, action.parameters);
    receipts.push({ actionId: action.id, adapter: action.adapter, result: result ?? null });
  }

  return {
    schemaVersion: 1,
    planId: plan.planId,
    status: "applied",
    evidence: { stateFingerprint: currentState.freshness.fingerprint },
    receipts,
  };
}
