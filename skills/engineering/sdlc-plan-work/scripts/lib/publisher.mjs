import { fingerprint } from "../../../sdlc-workflow/scripts/lib/json.mjs";

function nonEmpty(value, name) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${name} must be a non-empty string`);
  return value.trim();
}

function issueValue(value, name) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${name} must be an object`);
  }
  return {
    title: nonEmpty(value.title, `${name}.title`),
    body: nonEmpty(value.body, `${name}.body`),
  };
}

function orderedChildren(values) {
  if (!Array.isArray(values) || values.length === 0) {
    throw new Error("a coordinated feature needs at least one child");
  }
  const children = values.map((value, index) => {
    const issue = issueValue(value, `children[${index}]`);
    const key = nonEmpty(value.key, `children[${index}].key`);
    if (!/^[a-z0-9][a-z0-9-]*$/.test(key)) {
      throw new Error(`child key '${key}' must use lowercase letters, numbers, and hyphens`);
    }
    if (!Array.isArray(value.dependsOn) || value.dependsOn.some((item) => typeof item !== "string")) {
      throw new Error(`child '${key}' dependsOn must be an array of keys`);
    }
    return { key, ...issue, dependsOn: [...new Set(value.dependsOn)] };
  });
  const byKey = new Map();
  for (const child of children) {
    if (byKey.has(child.key)) throw new Error(`duplicate child key '${child.key}'`);
    byKey.set(child.key, child);
  }
  for (const child of children) {
    for (const blocker of child.dependsOn) {
      if (!byKey.has(blocker)) throw new Error(`child '${child.key}' has unknown blocker '${blocker}'`);
      if (blocker === child.key) throw new Error(`child '${child.key}' cannot block itself`);
    }
  }

  const pending = new Map(children.map((child, index) => [child.key, { child, index }]));
  const complete = new Set();
  const ordered = [];
  while (pending.size > 0) {
    const ready = [...pending.values()]
      .filter(({ child }) => child.dependsOn.every((key) => complete.has(key)))
      .sort((left, right) => left.index - right.index);
    if (ready.length === 0) {
      throw new Error(`child dependency cycle: ${[...pending.keys()].join(", ")}`);
    }
    for (const item of ready) {
      ordered.push(item.child);
      complete.add(item.child.key);
      pending.delete(item.child.key);
    }
  }
  return ordered;
}

function marker(planId, key) {
  return `<!-- agent-skills:sdlc-plan:${planId}:${key} -->`;
}

export function createPublishPlan(input, repositoryConfig) {
  if (input.schemaVersion !== 1) throw new Error("publisher input needs schemaVersion 1");
  const repository = nonEmpty(input.repository, "repository");
  if (!repository.includes("/")) throw new Error("repository must use owner/name form");
  if (!new Set(["single", "feature"]).has(input.mode)) {
    throw new Error("mode must be 'single' or 'feature'");
  }

  const normalized = input.mode === "single"
    ? { schemaVersion: 1, mode: "single", repository, issue: issueValue(input.issue, "issue") }
    : {
        schemaVersion: 1,
        mode: "feature",
        repository,
        parent: issueValue(input.parent, "parent"),
        children: orderedChildren(input.children),
      };
  const sourceId = fingerprint({
    normalized,
    labels: normalized.mode === "feature"
      ? {
          feature: repositoryConfig.featureLabel,
          child: repositoryConfig.childLabel,
          ready: repositoryConfig.readyLabel,
        }
      : {},
  });
  if (normalized.mode === "single") {
    const content = {
      ...normalized,
      issue: {
        ...normalized.issue,
        labels: [],
        marker: marker(sourceId, "issue"),
      },
    };
    return { ...content, planId: fingerprint(content) };
  }
  const content = {
    ...normalized,
    parent: {
      ...normalized.parent,
      labels: [repositoryConfig.featureLabel],
      marker: marker(sourceId, "parent"),
    },
    children: normalized.children.map((child) => ({
      ...child,
      labels: [
        repositoryConfig.childLabel,
        ...(child.dependsOn.length === 0 ? [repositoryConfig.readyLabel] : []),
      ],
      marker: marker(sourceId, child.key),
    })),
  };
  return { ...content, planId: fingerprint(content) };
}

function markedBody(item, parentNumber) {
  const body = parentNumber
    ? item.body.replaceAll("{parent}", String(parentNumber))
    : item.body;
  return `${body.trim()}\n\n${item.marker}\n`;
}

async function ensureIssue(adapter, repository, item, parentNumber) {
  const existing = await adapter.findByMarker(repository, item.marker);
  if (existing) return { ...existing, reused: true };
  const created = await adapter.createIssue(repository, {
    title: item.title,
    body: markedBody(item, parentNumber),
    labels: item.labels,
  });
  return { ...created, reused: false };
}

export async function applyPublishPlan(plan, approvedPlanId, adapter) {
  if (plan.planId !== approvedPlanId) {
    throw new Error("the approved plan ID does not match this publish plan");
  }
  const recreated = createPublishPlan(plan, {
    featureLabel: plan.parent?.labels?.[0],
    childLabel: plan.children?.[0]?.labels?.[0],
    readyLabel: plan.children
      ?.find((child) => child.dependsOn.length === 0)
      ?.labels?.find((label) => label !== plan.children?.[0]?.labels?.[0]),
  });
  if (recreated.planId !== plan.planId) throw new Error("publish plan content does not match its planId");

  if (plan.mode === "single") {
    const issue = await ensureIssue(adapter, plan.repository, plan.issue);
    return { schemaVersion: 1, planId: plan.planId, mode: "single", issue };
  }

  const parent = await ensureIssue(adapter, plan.repository, plan.parent);
  const created = new Map();
  const children = [];
  for (const child of plan.children) {
    const issue = await ensureIssue(adapter, plan.repository, child, parent.number);
    created.set(child.key, issue);
    await adapter.addSubIssue(plan.repository, parent.number, issue.id);
    for (const blockerKey of child.dependsOn) {
      await adapter.addBlocker(plan.repository, issue.number, created.get(blockerKey).id);
    }
    children.push({ key: child.key, ...issue });
  }
  return {
    schemaVersion: 1,
    planId: plan.planId,
    mode: "feature",
    parent,
    children,
  };
}
