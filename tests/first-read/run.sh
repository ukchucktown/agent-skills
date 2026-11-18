#!/usr/bin/env bash
# Self-test for skills/writing/first-read/scripts/lint.py.
#
#   ./tests/first-read/run.sh
#
# Each case asserts a hard count and a soft count against a fixture. When you
# change a check, run this first. A drop in the violations count means the
# check stopped working. A rise in the compliant count means a false positive.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

LINT="python3 skills/writing/first-read/scripts/lint.py"
fail=0

count() { # file, bucket, optional rule
  $LINT "$1" --soft --json | python3 -c \
    "import json,sys; f=json.load(sys.stdin)['$2']; r='${3:-}'; print(len([x for x in f if not r or x['rule']==r]))"
}

expect_rule() { # label, file, rule, want (soft bucket)
  local got
  got="$(count "$2" soft "$3")"
  if [ "$got" = "$4" ]; then
    printf 'ok    %-28s %s=%s\n' "$1" "$3" "$got"
  else
    printf 'FAIL  %-28s %s=%s want %s\n' "$1" "$3" "$got" "$4"
    fail=1
  fi
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

expect "violations: hard"  tests/first-read/fixtures/violations.md hard 11
expect "violations: soft"  tests/first-read/fixtures/violations.md soft 12
expect "compliant: hard"   tests/first-read/fixtures/compliant.md  hard 0
expect "compliant: soft"   tests/first-read/fixtures/compliant.md  soft 0
expect "issue: hard"       tests/first-read/fixtures/issue.md      hard 0
expect "spec: hard"        tests/first-read/fixtures/spec.md       hard 0
expect "spec: soft"        tests/first-read/fixtures/spec.md       soft 0

# Rhythm (S14). chop.md holds one row of short sentences, one row of sentences
# with the same first two words, and a numbered procedure that is exempt.
# flow.md holds the same facts in joined sentences.
expect      "chop: hard"   tests/first-read/fixtures/chop.md  hard 0
expect      "chop: soft"   tests/first-read/fixtures/chop.md  soft 2
expect_rule "chop: S14"    tests/first-read/fixtures/chop.md  S14  2
expect      "flow: hard"   tests/first-read/fixtures/flow.md  hard 0
expect      "flow: soft"   tests/first-read/fixtures/flow.md  soft 0

# long.md holds one row of three long sentences. No sentence is over the S1
# target, so S14 is the only finding.
expect      "long: hard"   tests/first-read/fixtures/long.md  hard 0
expect      "long: soft"   tests/first-read/fixtures/long.md  soft 1
expect_rule "long: S14"    tests/first-read/fixtures/long.md  S14  1

# Casual profile. casual.md has two contractions and no other finding.
expect      "casual: default profile" tests/first-read/fixtures/casual.md hard 2
got="$($LINT tests/first-read/fixtures/casual.md --profile casual --soft --json \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['hard']), len(d['soft']))")"
if [ "$got" = "0 0" ]; then
  echo "ok    casual: casual profile       hard=0 soft=0"
else
  echo "FAIL  casual: casual profile       got '$got' want '0 0'"; fail=1
fi

# AI tells. tells.md holds one occurrence of each tell that the linter finds.
expect      "tells: soft"  tests/first-read/fixtures/tells.md soft 5
for rule in T1 T3 T6 T8 T11; do
  expect_rule "tells: $rule" tests/first-read/fixtures/tells.md "$rule" 1
done

# Our own prose must pass the hard tier.
for f in docs/first-read.md \
         skills/writing/first-read/NOTICE.md \
         skills/writing/first-read/SKILL.md \
         skills/writing/first-read/references/*.md; do
  [ -e "$f" ] || continue
  expect "self: $(basename "$f")" "$f" hard 0
done

# Exit code contract.
$LINT tests/first-read/fixtures/compliant.md >/dev/null
[ $? -eq 0 ] && echo "ok    exit 0 when clean" || { echo "FAIL  exit code"; fail=1; }
$LINT tests/first-read/fixtures/violations.md >/dev/null
[ $? -eq 1 ] && echo "ok    exit 1 when hard findings" || { echo "FAIL  exit code"; fail=1; }

exit $fail
