#!/usr/bin/env bash
# Self-test for skills/first-read/scripts/lint.py.
#
#   ./scripts/test_lint.sh
#
# Each case asserts a hard count and a soft count against a fixture. When you
# change a check, run this first. A drop in the violations count means the
# check stopped working. A rise in the compliant count means a false positive.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

LINT="python3 skills/first-read/scripts/lint.py"
fail=0

count() { # file, bucket
  $LINT "$1" --soft --json | python3 -c \
    "import json,sys; print(len(json.load(sys.stdin)['$2']))"
}

expect() { # label, file, bucket, want
  local got
  got="$(count "$2" "$3")"
  if [ "$got" = "$4" ]; then
    printf 'ok    %-28s %s=%s\n' "$1" "$3" "$got"
  else
    printf 'FAIL  %-28s %s=%s want %s\n' "$1" "$3" "$got" "$4"
    fail=1
  fi
}

expect "violations: hard"  tests/fixtures/violations.md hard 11
expect "violations: soft"  tests/fixtures/violations.md soft 12
expect "compliant: hard"   tests/fixtures/compliant.md  hard 0
expect "compliant: soft"   tests/fixtures/compliant.md  soft 0
expect "issue: hard"       tests/fixtures/issue.md      hard 0
expect "spec: hard"        tests/fixtures/spec.md       hard 0
expect "spec: soft"        tests/fixtures/spec.md       soft 0

# Our own prose must pass the hard tier.
for f in NOTICE.md README.md skills/first-read/SKILL.md \
         skills/first-read/references/*.md \
         output-styles/*.md; do
  [ -e "$f" ] || continue
  expect "self: $(basename "$f")" "$f" hard 0
done

# Exit code contract.
$LINT tests/fixtures/compliant.md >/dev/null
[ $? -eq 0 ] && echo "ok    exit 0 when clean" || { echo "FAIL  exit code"; fail=1; }
$LINT tests/fixtures/violations.md >/dev/null
[ $? -eq 1 ] && echo "ok    exit 1 when hard findings" || { echo "FAIL  exit code"; fail=1; }

exit $fail
