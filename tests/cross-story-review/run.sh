#!/usr/bin/env bash
# Structure and coverage check for the cross-story-review fixtures.
#
#   ./tests/cross-story-review/run.sh
#
# This check is deterministic and reads only files in this repository. It does
# not run the skill. It proves that the fixtures and the criteria stay in
# step: every run names a real set and real criteria, every criterion has a
# run that must trigger it, and every key of an expectation is a key of a
# story. It also proves that the grader rejects wrong results.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

python3 - <<'PY'
import json, pathlib, re, sys

skill = pathlib.Path("skills/in-progress/cross-story-review")
fx = pathlib.Path("tests/cross-story-review/fixtures")
fail = 0

def check(ok, label):
    global fail
    print(("ok    " if ok else "FAIL  ") + label)
    if not ok:
        fail = 1

text = (skill / "references/criteria.md").read_text()
criteria = re.findall(r"^### ([a-z-]+)$", text, re.M)
check(len(criteria) == len(set(criteria)), "criterion names are unique")

skill_md = (skill / "SKILL.md").read_text()
counts = [int(n) for n in re.findall(r"(\d+) criteria", skill_md)]
check(bool(counts) and all(n == len(criteria) for n in counts),
      f"SKILL.md criterion counts match criteria.md ({len(criteria)})")
words = {7: "Seven"}
m = re.search(r"^(\w+) criteria for a set of stories", text, re.M)
check(bool(m) and words.get(len(criteria)) == m.group(1),
      "criteria.md intro count matches its headings")

labels = re.findall(r"^Label: \*\*(.+)\*\*$", text, re.M)
check(len(labels) == len(criteria) and len(set(labels)) == len(labels),
      "every criterion has one unique report label")
check(all(re.search(rf"^### {c}\n(?:.*\n)*?- Sources: ", text, re.M) for c in criteria),
      "every criterion names its sources")

for ref in set(re.findall(r"`references/([a-z-]+\.md)`", skill_md)):
    check((skill / "references" / ref).is_file(), f"SKILL.md pointer resolves: {ref}")

front = re.match(r"---\n(.*?)\n---\n", skill_md, re.S)
check(bool(front) and "name: cross-story-review" in front.group(1)
      and "description:" in front.group(1), "SKILL.md has its name and description")

expected = json.loads((fx / "expected.json").read_text())
covered = set()
for name, e in sorted(expected.items()):
    folder = fx / "sets" / e["set"]
    check(folder.is_dir(), f"{name}: set folder exists")
    keys = set()
    for story in sorted((folder / "stories").glob("*.md")):
        m = re.match(r"Key: (\S+)\n", story.read_text())
        check(bool(m), f"{name}: {story.name} starts with its key")
        if m:
            keys.add(m.group(1))
    check(len(keys) >= 2, f"{name}: the set has two or more stories")
    reference = folder / "reference.md"
    ids = set(re.findall(r"^\| (R\d+) \|", reference.read_text(), re.M)) if reference.is_file() else set()
    if e["reference"]:
        check(bool(ids), f"{name}: the scope reference exists")
    if e["reports"]:
        check(any((folder / "reports").glob("*.md")), f"{name}: a single-story report exists")
    items = e.get("must_find", []) + e.get("must_not_find", [])
    check({i["criterion"] for i in items} <= set(criteria), f"{name}: names only real criteria")
    used = {k for i in items for k in i.get("stories", []) + i.get("stories_any", [])}
    used |= {k for n in e.get("must_note", []) for k in (n["story"], n["answered_by"])}
    check(used <= keys, f"{name}: names only keys of its stories")
    refs = {i["reference"] for i in items if "reference" in i}
    check(refs <= ids, f"{name}: names only ids of its scope reference")
    check(set(e.get("skipped_exactly", [])) <= set(criteria), f"{name}: skips only real criteria")
    needs = {"coverage", "traceability"}
    check(set(e.get("skipped_exactly", [])) == (set() if e["reference"] else needs),
          f"{name}: skips exactly the criteria that need a scope reference")
    covered |= {i["criterion"] for i in e.get("must_find", [])}

missing = sorted(set(criteria) - covered)
check(not missing, "every criterion has a run that must trigger it"
      + (f" (missing: {', '.join(missing)})" if missing else ""))
check(any(e.get("no_findings") for e in expected.values()),
      "one run is a clean set with no finding")

# The grader must reject wrong results.
sys.path.insert(0, "tests/cross-story-review")
from grade import grade

clean = expected["clean"]
clinic = expected["clinic"]
bare = {"findings": [], "questions": [], "notes": [],
        "skipped": ["coverage", "traceability"]}
check(not grade(bare, clean, criteria), "grader accepts a clean result for the clean set")
alarm = {**bare, "findings": [{"criterion": "overlap", "stories": ["EX-1", "EX-4"],
                               "severity": "material"}]}
check(bool(grade(alarm, clean, criteria)), "grader rejects a finding in the clean set")
check(bool(grade({**bare, "skipped": []}, clean, criteria)),
      "grader rejects a run with no scope reference that skips nothing")
full = {"findings": [
            {"criterion": "overlap", "stories": ["CL-3", "CL-7"], "severity": "material"},
            {"criterion": "contradiction", "stories": ["CL-3", "CL-5"], "severity": "blocking"},
            {"criterion": "contradiction", "stories": ["CL-6"], "reference": "R7", "severity": "material"},
            {"criterion": "dependency", "stories": ["CL-6", "CL-3"], "severity": "material"},
            {"criterion": "coverage", "reference": "R6", "severity": "material"},
            {"criterion": "terms", "stories": ["CL-5", "CL-7", "CL-3"], "severity": "minor"}],
        "questions": [
            {"criterion": "missing-capability", "stories": ["CL-8"]},
            {"criterion": "traceability", "stories": ["CL-9"]}],
        "skipped": [],
        "notes": [{"story": "CL-6", "answered_by": "CL-3"}]}
check(not grade(full, clinic, criteria), "grader accepts a complete result for the clinic set")
without = {**full, "findings": [f for f in full["findings"] if f.get("stories") != ["CL-3", "CL-5"]]}
check(bool(grade(without, clinic, criteria)), "grader rejects a result with a planted problem absent")
soft = {**full, "findings": [dict(f, severity="minor") if f.get("stories") == ["CL-3", "CL-5"] else f
                             for f in full["findings"]]}
check(bool(grade(soft, clinic, criteria)), "grader rejects a contradiction with a minor severity")
guard = {**full, "findings": full["findings"] + [
    {"criterion": "overlap", "stories": ["CL-3", "CL-10"], "severity": "material"}]}
check(bool(grade(guard, clinic, criteria)), "grader rejects a false alarm that a guard excludes")
later = {**full, "findings": full["findings"] + [
    {"criterion": "coverage", "reference": "R8", "severity": "material"}]}
check(bool(grade(later, clinic, criteria)), "grader rejects a gap for a requirement outside the set")
trace = {**full, "findings": full["findings"] + [
    {"criterion": "traceability", "stories": ["CL-9"], "severity": "minor"}]}
check(bool(grade(trace, clinic, criteria)), "grader rejects traceability as a finding")
check(bool(grade({**full, "notes": []}, clinic, criteria)), "grader rejects a result with the note absent")
invented = {**full, "questions": full["questions"] + [{"criterion": "made-up", "stories": ["CL-1"]}]}
check(bool(grade(invented, clinic, criteria)), "grader rejects a criterion that criteria.md does not have")
asfinding = {**full, "questions": [q for q in full["questions"] if q["criterion"] != "missing-capability"],
             "findings": full["findings"] + [
                 {"criterion": "missing-capability", "stories": ["CL-8"], "severity": "material"}]}
check(bool(grade(asfinding, clinic, criteria)), "grader rejects a missing capability as a finding where a question is due")

sys.exit(fail)
PY
