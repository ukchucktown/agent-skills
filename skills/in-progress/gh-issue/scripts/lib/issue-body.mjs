const CHILD_HEADINGS = new Set([
  "children",
  "child issue",
  "child issues",
  "sub-issue",
  "sub-issues",
  "subissue",
  "subissues",
  "task",
  "tasks",
  "work item",
  "work items",
  "implementation issue",
  "implementation issues",
]);

const PARENT_HEADINGS = new Set(["parent", "parent issue"]);
const BLOCKER_HEADINGS = new Set([
  "blocked by",
  "blockers",
  "dependencies",
  "depends on",
]);

function normalizeHeading(value) {
  return value
    .replace(/[*_`]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
}

export function issueReferences(value) {
  const found = [];
  const seen = new Set();
  const patterns = [
    /(?:^|[^\w])#(\d+)\b/g,
    /https?:\/\/github\.com\/[^/\s]+\/[^/\s]+\/issues\/(\d+)\b/g,
  ];

  for (const pattern of patterns) {
    for (const match of value.matchAll(pattern)) {
      const number = Number.parseInt(match[1], 10);
      if (number > 0 && !seen.has(number)) {
        seen.add(number);
        found.push(number);
      }
    }
  }

  return found;
}

function appendUnique(target, values) {
  for (const value of values) {
    if (!target.includes(value)) target.push(value);
  }
}

function inlineField(line, name) {
  const cleaned = line.replace(/^\s*[-*+]\s+/, "");
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = cleaned.match(
    new RegExp(`^(?:\\*\\*)?${escaped}(?: issue)?(?:\\*\\*)?\\s*:\\s*(.*)$`, "i"),
  );
  return match?.[1] ?? null;
}

export function parseIssueBody(body = "") {
  const result = {
    parentNumbers: [],
    childNumbers: [],
    blockedByNumbers: [],
  };

  let section = null;
  for (const line of body.split(/\r?\n/)) {
    const heading = line.match(/^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$/);
    if (heading) {
      const name = normalizeHeading(heading[1]);
      section = CHILD_HEADINGS.has(name)
        ? "children"
        : PARENT_HEADINGS.has(name)
          ? "parent"
          : BLOCKER_HEADINGS.has(name)
            ? "blocked"
            : null;
      continue;
    }

    const parentField = inlineField(line, "parent");
    if (parentField !== null) {
      appendUnique(result.parentNumbers, issueReferences(parentField));
      continue;
    }

    const blockerField = inlineField(line, "blocked by");
    if (blockerField !== null) {
      appendUnique(result.blockedByNumbers, issueReferences(blockerField));
      continue;
    }

    const references = issueReferences(line);
    if (section === "parent") {
      appendUnique(result.parentNumbers, references);
    } else if (section === "children") {
      appendUnique(result.childNumbers, references);
    } else if (section === "blocked") {
      appendUnique(result.blockedByNumbers, references);
    } else {
      const checklist = line.match(/^\s*[-*+]\s+\[[ xX]\]\s+(.+)$/);
      if (
        checklist &&
        /^(?:#\d+\b|https?:\/\/github\.com\/[^/\s]+\/[^/\s]+\/issues\/\d+\b|\[[^\]]+\]\(https?:\/\/github\.com\/[^/\s]+\/[^/\s]+\/issues\/\d+\))/i.test(
          checklist[1],
        )
      ) {
        appendUnique(result.childNumbers, references);
      }
    }
  }

  return result;
}
