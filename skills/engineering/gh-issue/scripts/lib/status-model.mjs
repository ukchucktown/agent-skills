import { parseIssueBody } from "./issue-body.mjs";

function summaries(value) {
  if (Array.isArray(value)) return value;
  return value?.nodes ?? [];
}

export function normalizeIssue(raw) {
  return {
    number: Number(raw.number),
    title: raw.title ?? "",
    state: String(raw.state ?? "OPEN").toUpperCase(),
    url: raw.url ?? null,
    body: raw.body ?? "",
    updatedAt: raw.updatedAt ?? null,
    author: raw.author?.login ?? raw.author ?? null,
    assignees: summaries(raw.assignees).map(
      (entry) => entry.login ?? entry.name ?? String(entry),
    ),
    labels: summaries(raw.labels).map((entry) => entry.name ?? String(entry)),
    parent: raw.parent ? normalizeSummary(raw.parent) : null,
    subIssues: summaries(raw.subIssues).map(normalizeSummary),
    blockedBy: summaries(raw.blockedBy).map(normalizeSummary),
  };
}

function normalizeSummary(raw) {
  return {
    number: Number(raw.number),
    title: raw.title ?? "",
    state: String(raw.state ?? "OPEN").toUpperCase(),
    url: raw.url ?? null,
  };
}

function addEvidence(map, number, source) {
  if (!Number.isInteger(number) || number < 1) return;
  const sources = map.get(number) ?? [];
  if (!sources.includes(source)) sources.push(source);
  map.set(number, sources);
}

function evidenceList(map) {
  return [...map.entries()].map(([number, sources]) => ({ number, sources }));
}

export function branchMatchesIssue(branch, issueNumber) {
  if (!branch) return false;
  const escaped = String(issueNumber).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(
    `(?:^|/)(?:issue[-/]|integration/)${escaped}(?:[-/]|$)`,
    "i",
  ).test(branch);
}

function prMatchesIssue(pr, issueNumber) {
  if (branchMatchesIssue(pr.headRefName, issueNumber)) return true;
  if (
    summaries(pr.closingIssuesReferences).some(
      (issue) => Number(issue.number) === issueNumber,
    )
  ) {
    return true;
  }
  const escaped = String(issueNumber).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(
    `(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|issue|tracks?)\\s*:?\\s*#${escaped}\\b`,
    "i",
  ).test(pr.body ?? "");
}

function workForIssue(workState, issueNumber) {
  const branches = (workState.branches ?? []).filter((branch) =>
    branchMatchesIssue(branch.name ?? branch, issueNumber),
  );
  const worktrees = (workState.worktrees ?? []).filter((worktree) =>
    branchMatchesIssue(worktree.branch, issueNumber),
  );
  const pullRequests = (workState.pullRequests ?? []).filter((pr) =>
    prMatchesIssue(pr, issueNumber),
  );

  return { branches, worktrees, pullRequests };
}

function checksForPullRequest(pr) {
  return (pr.statusCheckRollup ?? []).map((check) => ({
    name: check.name ?? check.context ?? check.workflowName ?? "check",
    status: check.status ?? null,
    conclusion: check.conclusion ?? check.state ?? null,
    url: check.detailsUrl ?? check.targetUrl ?? null,
  }));
}

function publicPullRequest(pr) {
  return {
    number: Number(pr.number),
    title: pr.title ?? "",
    state: String(pr.state ?? "OPEN").toUpperCase(),
    isDraft: Boolean(pr.isDraft),
    head: pr.headRefName ?? null,
    base: pr.baseRefName ?? null,
    url: pr.url ?? null,
    mergedAt: pr.mergedAt ?? null,
    checks: checksForPullRequest(pr),
  };
}

function issueSummary(issue) {
  return {
    number: issue.number,
    title: issue.title,
    state: issue.state,
    url: issue.url,
    assignees: issue.assignees,
    labels: issue.labels,
  };
}

function hasBlockedLabel(issue) {
  return issue.labels.some((label) => /^blocked(?::|$)/i.test(label));
}

function nodeState(issue, blockers, work) {
  if (issue.state === "CLOSED") return "completed";
  if (blockers.some((blocker) => blocker.state !== "CLOSED") || hasBlockedLabel(issue)) {
    return "blocked";
  }
  if (
    work.branches.length > 0 ||
    work.worktrees.length > 0 ||
    work.pullRequests.length > 0
  ) {
    return "in_progress";
  }
  return "ready";
}

function groupChildren(children) {
  const grouped = { ready: [], in_progress: [], blocked: [], completed: [] };
  for (const child of children) grouped[child.workflowState].push(child.issue);
  return grouped;
}

function findLeaves(node, target = []) {
  if (node.classification === "standalone") {
    target.push(node);
    return target;
  }
  for (const child of node.children) findLeaves(child, target);
  return target;
}

function chooseRecommendation(tree) {
  const leaves = findLeaves(tree);
  const started = leaves.find((node) => node.workflowState === "in_progress");
  if (started) {
    return {
      issue: started.issue,
      reason: "Already has work in progress and is not complete.",
    };
  }

  const ready = leaves.find((node) => node.workflowState === "ready");
  if (ready) {
    return {
      issue: ready.issue,
      reason: "First open, unblocked standalone issue in hierarchy order.",
    };
  }

  return null;
}

function compactHierarchy(node) {
  return {
    issue: node.issue,
    classification: node.classification,
    workflowState: node.workflowState,
    children: node.children.map(compactHierarchy),
  };
}

function nextAction(tree, ancestors, focusPr, conflicts, recommendation) {
  if (conflicts.length > 0) return "Resolve the reported hierarchy conflict.";

  if (tree.issue.state === "CLOSED") {
    if (ancestors.length > 0) {
      const parent = ancestors.at(-1);
      return `Return to parent issue #${parent.number}.`;
    }
    return `Run gh-issue clean ${tree.issue.number} when its stable-branch PR is merged.`;
  }

  const openPr = focusPr.find((pr) => pr.state === "OPEN");
  if (openPr) return `Review pull request #${openPr.number}; merging remains a human action.`;
  const mergedPr = focusPr.find((pr) => pr.mergedAt);
  if (mergedPr) {
    return `Issue #${tree.issue.number} remains open after pull request #${mergedPr.number} merged. Inspect the issue-closing automation.`;
  }

  if (tree.classification === "compound") {
    if (recommendation) return `Choose an issue to start; recommended #${recommendation.issue.number}.`;
    if (tree.children.every((child) => child.workflowState === "completed")) {
      return `Run gh-issue finish ${tree.issue.number} to prepare its integration PR.`;
    }
    return "Resolve child blockers before finishing this compound issue.";
  }

  if (tree.workflowState === "in_progress") {
    return `Run gh-issue finish ${tree.issue.number} when the work is ready for review.`;
  }
  if (tree.workflowState === "blocked") return "Resolve the reported blockers.";
  return `Run gh-issue start ${tree.issue.number} to prepare its worktree.`;
}

export async function buildStatus({ client, workState, issueNumber, maxIssues = 200 }) {
  const issueCache = new Map();
  const referenceCache = new Map();
  const conflicts = [];
  const warnings = [];

  async function getIssue(number) {
    if (!issueCache.has(number)) {
      if (issueCache.size >= maxIssues) {
        throw new Error(`Issue hierarchy exceeds the ${maxIssues}-issue inspection limit.`);
      }
      issueCache.set(number, normalizeIssue(await client.getIssue(number)));
    }
    return issueCache.get(number);
  }

  async function referencing(number) {
    if (!referenceCache.has(number)) {
      referenceCache.set(
        number,
        (await client.searchIssuesReferencing(number)).map(normalizeIssue),
      );
    }
    return referenceCache.get(number);
  }

  async function parentEvidence(issue) {
    const evidence = new Map();
    if (issue.parent) addEvidence(evidence, issue.parent.number, "github-parent");

    const parsed = parseIssueBody(issue.body);
    for (const number of parsed.parentNumbers) addEvidence(evidence, number, "child-body");

    for (const candidate of await referencing(issue.number)) {
      if (candidate.number === issue.number) continue;
      const candidateBody = parseIssueBody(candidate.body);
      if (candidateBody.childNumbers.includes(issue.number)) {
        addEvidence(evidence, candidate.number, "parent-body");
      }
    }
    return evidence;
  }

  async function childrenEvidence(issue) {
    const evidence = new Map();
    for (const child of issue.subIssues) {
      addEvidence(evidence, child.number, "github-sub-issue");
    }

    const parsed = parseIssueBody(issue.body);
    for (const number of parsed.childNumbers) addEvidence(evidence, number, "parent-body");

    for (const candidate of await referencing(issue.number)) {
      if (candidate.number === issue.number) continue;
      const candidateBody = parseIssueBody(candidate.body);
      if (candidateBody.parentNumbers.includes(issue.number)) {
        addEvidence(evidence, candidate.number, "child-body");
      }
    }
    return evidence;
  }

  async function blockersFor(issue) {
    const evidence = new Map();
    for (const blocker of issue.blockedBy) {
      addEvidence(evidence, blocker.number, "github-blocked-by");
    }
    for (const number of parseIssueBody(issue.body).blockedByNumbers) {
      addEvidence(evidence, number, "issue-body");
    }

    const blockers = [];
    for (const { number, sources } of evidenceList(evidence)) {
      const blocker = await getIssue(number);
      blockers.push({ ...issueSummary(blocker), sources });
    }
    return blockers;
  }

  const focus = await getIssue(issueNumber);
  const ancestors = [];
  const ancestorNumbers = new Set([focus.number]);
  let cursor = focus;

  while (true) {
    const evidence = await parentEvidence(cursor);
    const candidates = evidenceList(evidence);
    if (candidates.length === 0) break;
    if (candidates.length > 1) {
      conflicts.push({
        kind: "multiple_parents",
        issue: issueSummary(cursor),
        candidates,
      });
      break;
    }

    const parentNumber = candidates[0].number;
    if (ancestorNumbers.has(parentNumber)) {
      conflicts.push({
        kind: "hierarchy_cycle",
        issue: issueSummary(cursor),
        parentNumber,
      });
      break;
    }

    const parent = await getIssue(parentNumber);
    ancestors.unshift({ ...issueSummary(parent), sources: candidates[0].sources });
    ancestorNumbers.add(parentNumber);
    cursor = parent;
  }

  const building = new Set();
  async function buildNode(issue, expectedParent = null) {
    if (building.has(issue.number)) {
      conflicts.push({ kind: "hierarchy_cycle", issue: issueSummary(issue) });
      return null;
    }
    building.add(issue.number);

    if (expectedParent !== null) {
      const evidence = evidenceList(await parentEvidence(issue));
      const otherParents = evidence.filter((entry) => entry.number !== expectedParent);
      if (otherParents.length > 0) {
        conflicts.push({
          kind: "conflicting_parent",
          issue: issueSummary(issue),
          expectedParent,
          candidates: evidence,
        });
      }
    }

    const blockers = await blockersFor(issue);
    const work = workForIssue(workState, issue.number);
    const childEvidence = evidenceList(await childrenEvidence(issue));
    const children = [];

    for (const entry of childEvidence) {
      const child = await getIssue(entry.number);
      const node = await buildNode(child, issue.number);
      if (node) children.push(node);
    }

    building.delete(issue.number);
    const classification = children.length > 0 ? "compound" : "standalone";
    let workflowState = nodeState(issue, blockers, work);
    if (
      classification === "compound" &&
      workflowState === "ready" &&
      children.some((child) => ["in_progress", "completed"].includes(child.workflowState))
    ) {
      workflowState = "in_progress";
    }
    return {
      issue: issueSummary(issue),
      classification,
      workflowState,
      blockers,
      work: {
        branches: work.branches,
        worktrees: work.worktrees,
        pullRequests: work.pullRequests.map(publicPullRequest),
      },
      children,
      childGroups: groupChildren(children),
    };
  }

  const tree = await buildNode(focus);
  if (!tree) throw new Error(`Could not resolve issue #${issueNumber}.`);

  const focusPullRequests = tree.work.pullRequests;
  const recommendation = chooseRecommendation(tree);
  if (issueCache.size >= maxIssues) {
    warnings.push(`Inspection stopped at the ${maxIssues}-issue limit.`);
  }

  return {
    kind: "status",
    repository: client.repository,
    stableBranch: client.defaultBranch,
    issue: tree.issue,
    classification: tree.classification,
    workflowState: tree.workflowState,
    ancestors,
    hierarchy: compactHierarchy(tree),
    work: tree.work,
    children: tree.childGroups,
    pullRequests: focusPullRequests,
    blockers: tree.blockers,
    conflicts,
    warnings,
    recommendation,
    nextAction: nextAction(tree, ancestors, focusPullRequests, conflicts, recommendation),
  };
}
