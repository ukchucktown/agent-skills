export const instructionStart = "<!-- agent-skills:global-instructions:start -->";
export const instructionEnd = "<!-- agent-skills:global-instructions:end -->";

function lineEnding(value) {
  return String(value ?? "").includes("\r\n") ? "\r\n" : "\n";
}

export function managedInstructionBlock(fragment, newline = "\n") {
  const content = String(fragment ?? "").replaceAll("\r\n", "\n").trim().replaceAll("\n", newline);
  return `${instructionStart}${newline}${content}${newline}${instructionEnd}`;
}

export function syncInstructionContent(current, fragment) {
  const original = String(current ?? "");
  const newline = lineEnding(original);
  const block = managedInstructionBlock(fragment, newline);
  const start = original.indexOf(instructionStart);
  const end = original.indexOf(instructionEnd);
  if (start === -1 && end === -1) {
    if (!original) return `${block}${newline}`;
    const separator = original.endsWith(`${newline}${newline}`)
      ? ""
      : original.endsWith(newline) ? newline : `${newline}${newline}`;
    return `${original}${separator}${block}${newline}`;
  }
  if (start === -1 || end === -1 || end < start) {
    throw new Error("instruction file has an incomplete agent-skills managed block");
  }
  const after = end + instructionEnd.length;
  if (original.indexOf(instructionStart, start + instructionStart.length) !== -1 ||
      original.indexOf(instructionEnd, after) !== -1) {
    throw new Error("instruction file has multiple agent-skills managed blocks");
  }
  return `${original.slice(0, start)}${block}${original.slice(after)}`;
}

export function inspectInstructionSync({ fragment, files }) {
  return Object.entries(files)
    .map(([path, current]) => {
      const desired = syncInstructionContent(current, fragment);
      return {
        path,
        status: current === desired ? "current" : "drifted",
        current: current ?? null,
        desired,
      };
    })
    .sort((left, right) => left.path.localeCompare(right.path));
}
