#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
status_command=$repository_root/skills/engineering/gh-issue/scripts/status.sh

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/gh-issue-status-tests.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

fake_bin=$temporary_directory/bin
mkdir -p "$fake_bin"

# Record any retired integration call without access to the real installation.
cat >"$fake_bin/supacode" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$(dirname -- "$0")/supacode-calls"
exit 70
EOF
chmod +x "$fake_bin/supacode"

# The fake gh builds each status response from one issue tree. Omitted node
# fields default to an open issue with no blockers, branches, or children.
cat >"$fake_bin/gh" <<'EOF'
#!/bin/sh
set -eu

[ "${1:-}:${2:-}" = "api:graphql" ] || {
  printf 'unexpected gh call: %s\n' "$*" >&2
  exit 70
}
number=
for argument in "$@"; do
  case "$argument" in
    number=*) number=${argument#number=} ;;
  esac
done
printf '%s\n' "$number" >>"$GH_CALL_LOG"
jq -n --argjson number "$number" --slurpfile tree "$GH_TREE" '
  def node($key):
    {state: "OPEN", blockedBy: [], branches: [], children: []} +
    ($tree[0][$key | tostring] // error("missing fixture node \($key)"));
  def blocked($key):
    {totalCount: (node($key).blockedBy | length),
     nodes: [node($key).blockedBy[] |
       {number: ., title: node(.).title, state: node(.).state, url: ""}]};
  def branches($key):
    {totalCount: (node($key).branches | length),
     nodes: [node($key).branches[] |
       {ref: {name: ., repository: {nameWithOwner: "example/status"}}}]};
  {data: {repository: {nameWithOwner: "example/status", issue: {
    number: $number,
    title: node($number).title,
    state: node($number).state,
    url: "https://github.com/example/status/issues/\($number)",
    body: "",
    updatedAt: "2026-10-02T00:00:00Z",
    assignees: {nodes: []},
    labels: {nodes: []},
    parent: null,
    blockedBy: blocked($number),
    linkedBranches: branches($number),
    subIssues: {
      totalCount: (node($number).children | length),
      nodes: [node($number).children[] as $child | {
        number: $child,
        title: node($child).title,
        state: node($child).state,
        url: "",
        subIssues: {totalCount: (node($child).children | length)},
        blockedBy: blocked($child),
        linkedBranches: branches($child)
      }]
    }
  }}}}'
EOF
chmod +x "$fake_bin/gh"

tree=$temporary_directory/tree.json
jq -n '
  {
    "200": {title: "Initiative", children: [210, 220, 230, 240]},
    "210": {title: "First epic", children: [211, 212]},
    "211": {title: "Linked task", branches: ["feat/issue-211-linked"]},
    "212": {title: "Blocked task", blockedBy: [211]},
    "220": {title: "Second epic", children: [221, 222, 223]},
    "221": {title: "Local task"},
    "222": {title: "Closed task", state: "CLOSED"},
    "223": {title: "Finished epic", children: [224]},
    "224": {title: "Finished task", state: "CLOSED"},
    "230": {title: "Blocked epic", blockedBy: [212], children: [231]},
    "231": {title: "Task under a blocked epic"},
    "240": {title: "Third epic", children: [241, 242]},
    "241": {title: "Ready task"},
    "242": {title: "Later task"},
    "300": {title: "Started initiative", children: [301, 302]},
    "301": {title: "First started task", branches: ["feat/issue-301-one"]},
    "302": {title: "Started epic", children: [303]},
    "303": {title: "Second started task", branches: ["feat/issue-303-two"]},
    "400": {title: "Wide initiative", children: [range(401; 431)]}
  } +
  ([range(401; 431) | {key: tostring, value: {title: "Empty epic \(.)", children: [500]}}] | from_entries) +
  {"500": {title: "Shared closed task", state: "CLOSED"}}
' >"$tree"

config_file=$temporary_directory/config.json
printf '%s\n' '{"projectSync":{"enabled":false},"repositories":{}}' >"$config_file"
call_log=$temporary_directory/gh-calls.log

primary=$temporary_directory/repository
git init -q -b main "$primary"
git -C "$primary" config user.name Test
git -C "$primary" config user.email test@example.com
git -C "$primary" remote add origin https://github.com/example/status.git
printf 'base\n' >"$primary/base.txt"
git -C "$primary" add base.txt
git -C "$primary" commit -q -m 'Initial state'
git -C "$primary" worktree add -q -b feat/issue-221-local "$temporary_directory/issue-221" main
printf 'committed\n' >"$temporary_directory/issue-221/committed.txt"
git -C "$temporary_directory/issue-221" add committed.txt
git -C "$temporary_directory/issue-221" commit -q -m 'Add issue 221 work'
printf 'draft\n' >"$temporary_directory/issue-221/draft.txt"
issue_221_path=$(git -C "$primary" worktree list --porcelain |
  awk '/^worktree .*issue-221$/ { print substr($0, 10) }')
git -C "$primary" worktree add -q -b feat/issue-2410-unrelated "$temporary_directory/issue-2410" main

run_status() {
  : >"$call_log"
  (cd "$primary" && PATH="$fake_bin:$PATH" \
    GH_TREE="$tree" \
    GH_CALL_LOG="$call_log" \
    FAKE_PRIMARY="$primary" \
    AGENT_SKILLS_CONFIG="$config_file" \
    "$status_command" example/status "$1")
}

expect_line() {
  printf '%s\n' "$1" | grep -Fx -- "$2" >/dev/null || {
    printf 'expected line: %s\nactual output:\n%s\n' "$2" "$1" >&2
    exit 1
  }
}

# The walk skips started work, backtracks out of subtrees with no candidate,
# and never queries a blocked subtree or a standalone issue.
output=$(run_status 200)
expect_line "$output" 'Recommendation: #241 Ready task'
expect_line "$output" 'Recommendation reason: first open unblocked standalone issue with no branch evidence'
expect_line "$output" 'Skipped as started:'
expect_line "$output" '- #211 Linked task'
expect_line "$output" '  Worktree: none (linked branch feat/issue-211-linked)'
expect_line "$output" '- #221 Local task'
expect_line "$output" "  Worktree: $issue_221_path [feat/issue-221-local]"
expect_line "$output" '  Evidence: branch commits 1 (last less than a minute ago), uncommitted changes 1'
expect_line "$output" 'Next: start issue #241'
queried=$(paste -sd ' ' "$call_log")
[ "$queried" = "200 210 220 223 240" ] || {
  printf 'unexpected queries: %s\n' "$queried" >&2
  exit 1
}

# When every ready standalone issue is started, the walk recommends nothing.
output=$(run_status 300)
expect_line "$output" 'Recommendation: none'
expect_line "$output" 'Recommendation reason: every open unblocked standalone descendant is already started'
expect_line "$output" '- #301 First started task'
expect_line "$output" '- #303 Second started task'
expect_line "$output" 'Next: continue or unblock the open child work'

# The walk stops at its query limit instead of a full hierarchy traversal.
output=$(run_status 400)
expect_line "$output" 'Recommendation: none'
expect_line "$output" 'Recommendation reason: unavailable because the walk reached its limit of 25 issue queries'
expect_line "$output" 'Skipped as started: none'
expect_line "$output" 'Next: inspect the descendant hierarchy'
query_count=$(wc -l <"$call_log" | tr -d ' ')
[ "$query_count" -eq 26 ] || {
  printf 'expected 26 queries, got %s\n' "$query_count" >&2
  exit 1
}

[ ! -e "$fake_bin/supacode-calls" ]

printf 'gh-issue status recommendation tests passed\n'
