#!/usr/bin/env python3
"""Cross-platform regression tests for the First Read linter."""

import glob
import json
import os
import subprocess
import sys


ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LINTER = os.path.join(ROOT, "skills", "writing", "first-read", "scripts", "lint.py")
FIXTURES = os.path.join(ROOT, "tests", "first-read", "fixtures")
failures = []


def run_linter(file_name, *arguments):
    return subprocess.run(
        [sys.executable, LINTER, file_name, *arguments],
        check=False,
        capture_output=True,
        text=True,
    )


def expect_count(label, file_name, bucket, wanted):
    result = run_linter(file_name, "--soft", "--json")
    try:
        actual = len(json.loads(result.stdout)[bucket])
    except (json.JSONDecodeError, KeyError) as error:
        failures.append(f"{label}: invalid JSON output: {error}")
        return
    if actual == wanted:
        print(f"ok    {label:28} {bucket}={actual}")
    else:
        failures.append(f"{label}: {bucket}={actual}, wanted {wanted}")


cases = [
    ("violations: hard", "violations.md", "hard", 11),
    ("violations: soft", "violations.md", "soft", 12),
    ("compliant: hard", "compliant.md", "hard", 0),
    ("compliant: soft", "compliant.md", "soft", 0),
    ("issue: hard", "issue.md", "hard", 0),
    ("spec: hard", "spec.md", "hard", 0),
    ("spec: soft", "spec.md", "soft", 0),
    ("swaps: hard", "swaps.md", "hard", 0),
    ("swaps: soft", "swaps.md", "soft", 3),
]

for case in cases:
    expect_count(case[0], os.path.join(FIXTURES, case[1]), case[2], case[3])

self_files = [
    os.path.join(ROOT, "docs", "first-read", "NOTICE.md"),
    os.path.join(ROOT, "docs", "first-read", "README.md"),
    os.path.join(ROOT, "skills", "writing", "first-read", "SKILL.md"),
]
self_files.extend(glob.glob(os.path.join(
    ROOT, "skills", "writing", "first-read", "references", "*.md"
)))
self_files.extend(glob.glob(os.path.join(
    ROOT, "integrations", "claude", "output-styles", "*.md"
)))
for file_name in self_files:
    expect_count(f"self: {os.path.basename(file_name)}", file_name, "hard", 0)

clean = run_linter(os.path.join(FIXTURES, "compliant.md"))
broken = run_linter(os.path.join(FIXTURES, "violations.md"))
if clean.returncode != 0:
    failures.append(f"clean fixture exit={clean.returncode}, wanted 0")
if broken.returncode != 1:
    failures.append(f"violation fixture exit={broken.returncode}, wanted 1")

if failures:
    print(f"FAIL  {len(failures)} First Read assertion(s)", file=sys.stderr)
    for failure in failures:
        print(f"- {failure}", file=sys.stderr)
    sys.exit(1)

print(f"Validated {len(cases) + len(self_files) + 2} First Read assertions.")
