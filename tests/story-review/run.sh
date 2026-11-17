#!/usr/bin/env bash
# Structure and coverage check for the story-review fixtures.
#
#   ./tests/story-review/run.sh
#
# This check is deterministic and reads only files in this repository. It does
# not run the skill. It proves that the fixtures and the criteria stay in step:
# every story has an expectation, every expectation names real criteria, and
# every criterion has a fixture that must trigger it.

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
        | set(e.get("must_question", []))
    check(used <= set(criteria), f"{name}: names only real criteria")
    if "item_type" in e:
        check(e["item_type"] in types, f"{name}: valid item type")
    else:
        check(bool(e.get("verdict")) and set(e["verdict"]) <= verdicts,
              f"{name}: valid verdict")
    if "checklist" in e:
        check((fx / e["checklist"]).is_file(), f"{name}: checklist file exists")
    covered |= set(e.get("must_find", [])) | set(e.get("must_question", []))

missing = sorted(set(criteria) - covered)
check(not missing, "every criterion has a fixture that must trigger it"
      + (f" (missing: {', '.join(missing)})" if missing else ""))

for ref in re.findall(r"`references/([a-z-]+\.md)`", skill_md):
    check((skill / "references" / ref).is_file(), f"SKILL.md pointer resolves: {ref}")

sys.exit(fail)
PY
