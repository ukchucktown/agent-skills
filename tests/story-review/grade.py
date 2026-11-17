#!/usr/bin/env python3
"""Grade story-review results against the fixture expectations.

    python3 tests/story-review/grade.py RESULTS.jsonl

RESULTS.jsonl holds one JSON object per line, one per reviewed fixture:

    {"story": "02-role", "item_type": "story", "verdict": "needs work",
     "findings": [{"criterion": "role", "severity": "material"}],
     "questions": [], "deferred": [], "checklist": {"1": "not met"}}

An agent that follows the skill on a fixture story produces the line. This
script only compares. It reads no file outside the path given and the fixture
folder next to it. Exit code 1 when any fixture fails or has no result.
"""
import json
import pathlib
import sys


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
