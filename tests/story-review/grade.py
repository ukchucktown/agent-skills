#!/usr/bin/env python3
"""Grade story-review results against the fixture expectations.

    python3 tests/story-review/grade.py RESULTS.jsonl

RESULTS.jsonl holds one JSON object per line, one per reviewed fixture:

    {"story": "02-role", "item_type": "story", "verdict": "needs work",
     "findings": [{"criterion": "role", "severity": "material"}],
     "questions": [], "deferred": [], "unverified": [],
     "checklist": {"1": "not met"}, "checklist_severity": {"1": "material"},
     "report_wording": "first-read"}

Fields:

- "findings": each has "criterion" and "severity" (blocking, material, or
  minor). An "estimable" finding also has "action": "decision" or
  "investigation".
- "questions", "deferred", "unverified": lists of criterion names.
- "checklist": item number to "met", "not met", or "cannot tell from the
  text". "checklist_severity": the severity of each "not met" item. An item
  with no entry counts as material.
- "report_wording": "first-read" when the agent wrote the report with the
  first-read skill, "built-in" when it used the wording rules in SKILL.md.

An agent that follows the skill on a fixture story produces the line. This
script only compares. It reads no file outside the path given and the fixture
folder next to it. Exit code 1 when any fixture fails or has no result.

Each result must also agree with itself: the verdict must be the one that the
highest severity among its findings and its "not met" checklist items gives.
"""
import json
import pathlib
import sys

SEVERITIES = ("minor", "material", "blocking")
VERDICT_FOR = {"minor": "ready", "material": "needs work", "blocking": "not ready"}
WORDINGS = ("first-read", "built-in")


def implied_verdict(result, problems):
    """Return the verdict that the severities in the result give."""
    states = {str(k): v for k, v in result.get("checklist", {}).items()}
    stated = {str(k): v for k, v in result.get("checklist_severity", {}).items()}
    severities = [f.get("severity") for f in result.get("findings", [])]
    severities += [stated.get(item, "material")
                   for item, state in states.items() if state == "not met"]
    for severity in severities:
        if severity not in SEVERITIES:
            problems.append(f"severity {severity!r} is not one of {list(SEVERITIES)}")
            return None
    if not severities:
        return "ready"
    return VERDICT_FOR[max(severities, key=SEVERITIES.index)]


def grade(result, want):
    problems = []
    if "item_type" in want:
        if result.get("item_type") != want["item_type"]:
            problems.append(f"item_type {result.get('item_type')!r}, want {want['item_type']!r}")
        return problems
    if result.get("item_type") != "story":
        problems.append(f"item_type {result.get('item_type')!r}, want 'story'")
    if result.get("verdict") not in want["verdict"]:
        problems.append(f"verdict {result.get('verdict')!r}, want one of {want['verdict']}")
    implied = implied_verdict(result, problems)
    if implied and result.get("verdict") != implied:
        problems.append(f"verdict {result.get('verdict')!r} contradicts the reported "
                        f"severities, which give {implied!r}")
    if result.get("report_wording") not in WORDINGS:
        problems.append(f"report_wording {result.get('report_wording')!r}, "
                        f"want one of {list(WORDINGS)}")
    elif "report_wording" in want and result["report_wording"] != want["report_wording"]:
        problems.append(f"report_wording {result['report_wording']!r}, "
                        f"want {want['report_wording']!r}")
    found = {f["criterion"] for f in result.get("findings", [])}
    asked = set(result.get("questions", []))
    for name in want.get("must_find", []):
        if name not in found:
            problems.append(f"no finding for {name}")
    for name in want.get("must_not_find", []):
        if name in found:
            problems.append(f"false alarm on {name}")
    for name in want.get("must_question", []):
        if name not in asked:
            problems.append(f"no question for {name}")
    unverified = set(result.get("unverified", []))
    for name in want.get("must_unverified", []):
        if name not in unverified:
            problems.append(f"{name} is not unverified")
    if "deferred_exactly" in want:
        deferred = sorted(set(result.get("deferred", [])))
        if deferred != sorted(want["deferred_exactly"]):
            problems.append(f"deferred {deferred}, want exactly {sorted(want['deferred_exactly'])}")
    actions = {f["criterion"]: f.get("action") for f in result.get("findings", [])}
    for name, action in want.get("actions", {}).items():
        if name in found and actions.get(name) != action:
            problems.append(f"{name} action {actions.get(name)!r}, want {action!r}")
    checklist = {str(k): v for k, v in result.get("checklist", {}).items()}
    for item in want.get("checklist_not_met", []):
        if checklist.get(str(item)) != "not met":
            problems.append(f"checklist item {item} is {checklist.get(str(item))!r}, want 'not met'")
    for item in want.get("checklist_met", []):
        if checklist.get(str(item)) != "met":
            problems.append(f"checklist item {item} is {checklist.get(str(item))!r}, want 'met'")
    return problems


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    here = pathlib.Path(__file__).resolve().parent
    expected = json.loads((here / "fixtures" / "expected.json").read_text())
    results = {}
    for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
        if line.strip():
            row = json.loads(line)
            results[row["story"]] = row
    failed = 0
    for name in sorted(expected):
        if name not in results:
            print(f"FAIL  {name}: no result")
            failed += 1
            continue
        problems = grade(results[name], expected[name])
        if problems:
            failed += 1
            print(f"FAIL  {name}: " + "; ".join(problems))
        else:
            print(f"ok    {name}")
    print(f"\n{len(expected) - failed} of {len(expected)} fixtures pass")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
