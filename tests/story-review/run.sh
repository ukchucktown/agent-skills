#!/usr/bin/env bash
# Structure and coverage check for the story-review fixtures.
#
#   ./tests/story-review/run.sh
#
# This check is deterministic and reads only files in this repository. It does
# not run the skill. It proves that the fixtures and the criteria stay in step:
# every story has an expectation, every expectation names real criteria, and
# every criterion has a fixture that must trigger it. It also proves that the
# grader rejects a result that contradicts itself.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

python3 - <<'PY'
import json, pathlib, re, sys

skill = pathlib.Path("skills/in-progress/story-review")
fx = pathlib.Path("tests/story-review/fixtures")
fail = 0

def check(ok, label):
    global fail
    print(("ok    " if ok else "FAIL  ") + label)
    if not ok:
        fail = 1

text = (skill / "references/criteria.md").read_text()
names = re.findall(r"^### ([a-z-]+)", text, re.M)
criteria = [n for n in names if n != "item-type"]
check("item-type" in names, "criteria.md has the item-type gate")
check(len(criteria) == len(set(criteria)), "criterion names are unique")

skill_md = (skill / "SKILL.md").read_text()
m = re.search(r"all (\d+) criteria", skill_md)
check(bool(m) and int(m.group(1)) == len(criteria),
      f"SKILL.md criterion count matches criteria.md ({len(criteria)})")
m = re.search(r"One gate and (\d+) criteria", text)
check(bool(m) and int(m.group(1)) == len(criteria),
      "criteria.md intro count matches its headings")

labels = re.findall(r"^Label: \*\*(.+)\*\*$", text, re.M)
check(len(labels) == len(criteria) and len(set(labels)) == len(labels),
      "every criterion has one unique report label")

expected = json.loads((fx / "expected.json").read_text())
stories = {p.stem for p in (fx / "stories").glob("*.md")}
check(stories == set(expected), "every story has an expectation, and the reverse")

verdicts = {"ready", "needs work", "not ready"}
types = {"constraint", "defect", "technical task"}
covered = set()
for name, e in sorted(expected.items()):
    used = set(e.get("must_find", [])) | set(e.get("must_not_find", [])) \
        | set(e.get("must_question", [])) | set(e.get("must_unverified", [])) \
        | set(e.get("deferred_exactly", [])) | set(e.get("actions", {}))
    check(used <= set(criteria), f"{name}: names only real criteria")
    if "item_type" in e:
        check(e["item_type"] in types, f"{name}: valid item type")
    else:
        check(bool(e.get("verdict")) and set(e["verdict"]) <= verdicts,
              f"{name}: valid verdict")
    if "checklist" in e:
        check((fx / e["checklist"]).is_file(), f"{name}: checklist file exists")
    covered |= set(e.get("must_find", [])) | set(e.get("must_question", []))

next_only = set(re.findall(r"^### ([a-z-]+) \(next only\)", text, re.M))
later = [e for e in expected.values() if e.get("horizon") == "later"]
check(bool(later) and all(set(e.get("deferred_exactly", [])) == next_only for e in later),
      f"each later-horizon fixture defers exactly the {len(next_only)} next-only criteria")

missing = sorted(set(criteria) - covered)
check(not missing, "every criterion has a fixture that must trigger it"
      + (f" (missing: {', '.join(missing)})" if missing else ""))

for ref in re.findall(r"`references/([a-z-]+\.md)`", skill_md):
    check((skill / "references" / ref).is_file(), f"SKILL.md pointer resolves: {ref}")

# The grader must reject a result that contradicts itself.
sys.path.insert(0, "tests/story-review")
from grade import grade

def result(**fields):
    base = {"item_type": "story", "verdict": "ready", "findings": [],
            "questions": [], "deferred": [], "unverified": [],
            "report_wording": "built-in"}
    return {**base, **fields}

minor = [{"criterion": "sentence", "severity": "minor"}]
blocking = [{"criterion": "sentence", "severity": "blocking"}]
seven = expected["22-later-epic"]["deferred_exactly"]
check(not grade(result(findings=minor), expected["10-sentence"]),
      "grader accepts a consistent result")
check(bool(grade(result(findings=blocking), expected["10-sentence"])),
      "grader rejects a blocking finding with a ready verdict")
check(not grade(result(deferred=seven), expected["22-later-epic"]),
      "grader accepts the exact later-horizon deferrals")
check(bool(grade(result(), expected["22-later-epic"])),
      "grader rejects a later-horizon result with no deferrals")
check(bool(grade(result(deferred=seven[:-1]), expected["22-later-epic"])),
      "grader rejects a later-horizon result with a deferral absent")
check(bool(grade(result(checklist={"1": "not met", "2": "met", "3": "met"},
                        checklist_severity={"1": "blocking"}),
                 expected["27-checklist-blocking"])),
      "grader rejects a blocking checklist item with a ready verdict")
check(not grade(result(checklist={"1": "met", "2": "not met", "3": "met"},
                       checklist_severity={"2": "minor"}),
                expected["28-checklist-minor"]),
      "grader accepts a minor checklist item with a ready verdict")
check(bool(grade(result(verdict="needs work",
                        findings=[{"criterion": "estimable", "severity": "material",
                                   "action": "investigation"}]),
                 expected["30-decision-unknown"])),
      "grader rejects an investigation where a decision is wanted")
check(bool(grade({k: v for k, v in result().items() if k != "report_wording"},
                 expected["31-passive-criterion"])),
      "grader rejects a result with no report_wording")

sys.exit(fail)
PY
