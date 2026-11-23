#!/usr/bin/env python3
"""Grade cross-story-review results against the fixture expectations.

    python3 tests/cross-story-review/grade.py RESULTS.jsonl

RESULTS.jsonl holds one JSON object per line, one per run of expected.json:

    {"run": "clinic",
     "findings": [{"criterion": "overlap", "stories": ["CL-3", "CL-7"],
                   "severity": "material"},
                  {"criterion": "coverage", "reference": "R6",
                   "severity": "material"}],
     "questions": [{"criterion": "traceability", "stories": ["CL-9"]}],
     "skipped": [],
     "notes": [{"story": "CL-6", "answered_by": "CL-3"}]}

Fields:

- "findings": each has "criterion", "severity" (blocking, material, or
  minor), and "stories" (the keys that it names). A finding against the scope
  reference has "reference" with the id of the requirement.
- "questions": each has "criterion" and "stories" or "reference".
- "skipped": the criteria that got the result skipped.
- "notes": each note on a single-story report, with the key of the story and
  the key of the story that answers it.

An agent that follows the skill on a fixture run produces the line. This
script only compares. Exit code 1 when a run fails or has no result.

An expectation names what a review must raise and what it must not raise. A
review can raise other findings and questions and still pass, unless the run
says "no_findings".
"""
import json
import pathlib
import re
import sys

SEVERITIES = ("minor", "material", "blocking")
NEEDS_REFERENCE = ("coverage", "traceability")


def matches(item, want):
    """True when a reported finding or question is the one that want names."""
    if item.get("criterion") != want["criterion"]:
        return False
    if "reference" in want:
        return item.get("reference") == want["reference"]
    stories = set(item.get("stories", []))
    if "stories_any" in want:
        return bool(stories & set(want["stories_any"]))
    return set(want["stories"]) <= stories


def grade(result, expected, criteria=None):
    """Return the list of problems of one result. Empty when it passes."""
    problems = []
    findings = result.get("findings", [])
    questions = result.get("questions", [])
    for finding in findings:
        if finding.get("severity") not in SEVERITIES:
            problems.append(f"finding {finding.get('criterion')}: no valid severity")
        if not finding.get("stories") and not finding.get("reference"):
            problems.append(f"finding {finding.get('criterion')}: names no story and no reference")
    if criteria is not None:
        for item in findings + questions:
            if item.get("criterion") not in criteria:
                problems.append(f"unknown criterion: {item.get('criterion')}")
    for item in findings:
        if item.get("criterion") == "traceability":
            problems.append("traceability gives a question, never a finding")
    for want in expected.get("must_find", []):
        pools = {"finding": findings, "question": questions,
                 "either": findings + questions}[want.get("as", "either")]
        found = [item for item in pools if matches(item, want)]
        label = want.get("reference") or "+".join(want.get("stories", want.get("stories_any", [])))
        if not found:
            problems.append(f"absent: {want['criterion']} for {label} as {want.get('as', 'either')}")
        elif "severity" in want and not any(
                item.get("severity") in want["severity"] for item in found):
            problems.append(f"wrong severity: {want['criterion']} for {label}")
    for want in expected.get("must_not_find", []):
        if any(matches(item, want) for item in findings):
            label = want.get("reference") or "+".join(
                want.get("stories", want.get("stories_any", [])))
            problems.append(f"false alarm: {want['criterion']} for {label}")
    if expected.get("no_findings") and findings:
        problems.append(f"a clean set got {len(findings)} finding(s)")
    skipped = set(result.get("skipped", []))
    if skipped != set(expected.get("skipped_exactly", [])):
        problems.append(f"skipped {sorted(skipped)}, expected {sorted(expected.get('skipped_exactly', []))}")
    for item in findings + questions:
        if item.get("criterion") in skipped:
            problems.append(f"{item['criterion']} is skipped and has a result")
    notes = result.get("notes", [])
    for want in expected.get("must_note", []):
        if not any(n.get("story") == want["story"] and n.get("answered_by") == want["answered_by"]
                   for n in notes):
            problems.append(f"absent note: {want['story']} answered by {want['answered_by']}")
    if expected.get("no_notes") and notes:
        problems.append("notes with no single-story reports")
    return problems


def main(path):
    here = pathlib.Path(__file__).parent
    expected = json.loads((here / "fixtures/expected.json").read_text())
    criteria = re.findall(
        r"^### ([a-z-]+)$",
        (here / "../../skills/in-progress/cross-story-review/references/criteria.md").read_text(),
        re.M)
    results = {}
    for line in pathlib.Path(path).read_text().splitlines():
        if line.strip():
            result = json.loads(line)
            results[result.get("run")] = result
    failed = 0
    for name, want in sorted(expected.items()):
        if name not in results:
            print(f"FAIL  {name}: no result")
            failed = 1
            continue
        problems = grade(results[name], want, criteria)
        print(("ok    " if not problems else "FAIL  ") + name
              + ("" if not problems else ": " + "; ".join(problems)))
        failed |= bool(problems)
    return failed


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
