#!/bin/sh
set -eu

usage() {
  echo "usage: status.sh [--project-override JSON] OWNER/REPOSITORY|. ISSUE_NUMBER" >&2
  exit 64
}

if [ "${1:-}" = "--project-override" ]; then
  [ "$#" -ge 2 ] || usage
  AGENT_SKILLS_PROJECT_OVERRIDE=$2
  export AGENT_SKILLS_PROJECT_OVERRIDE
  shift 2
fi
[ "$#" -eq 2 ] || usage

repository=$1
number=$2

case "$number" in
  ''|*[!0-9]*) usage ;;
esac
[ "$number" -gt 0 ] || usage

command -v jq >/dev/null 2>&1 || {
  echo "status.sh: jq is required" >&2
  exit 69
}

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
status_json=$("$script_directory/query.sh" status "$repository" "$number")

issue_exists=$(printf '%s' "$status_json" | jq -r '.data.repository.issue != null')
[ "$issue_exists" = "true" ] || {
  echo "status.sh: issue #$number was not found" >&2
  exit 2
}

canonical_repository=$(printf '%s' "$status_json" | jq -er '.data.repository.nameWithOwner')
issue_title=$(printf '%s' "$status_json" | jq -r '.data.repository.issue.title')
issue_state=$(printf '%s' "$status_json" | jq -r '.data.repository.issue.state')
issue_url=$(printf '%s' "$status_json" | jq -r '.data.repository.issue.url')
child_total=$(printf '%s' "$status_json" | jq -r '.data.repository.issue.subIssues.totalCount')
child_loaded=$(printf '%s' "$status_json" | jq -r '.data.repository.issue.subIssues.nodes | length')
open_child_count=$(printf '%s' "$status_json" | jq -r '[.data.repository.issue.subIssues.nodes[] | select(.state == "OPEN")] | length')
active_blocker_count=$(printf '%s' "$status_json" | jq -r '[.data.repository.issue.blockedBy.nodes[] | select(.state == "OPEN")] | length')
linked_branch_count=$(printf '%s' "$status_json" | jq -r '.data.repository.issue.linkedBranches.totalCount')

if [ "$child_total" -gt 0 ]; then
  issue_type=compound
else
  issue_type=standalone
fi

parent=$(printf '%s' "$status_json" | jq -r '
  .data.repository.issue.parent |
  if . == null then "none" else "#\(.number) \(.title) [\(.state)]" end
')
blockers=$(printf '%s' "$status_json" | jq -r '
  [.data.repository.issue.blockedBy.nodes[] |
    select(.state == "OPEN") |
    "#\(.number) \(.title)"] |
  if length == 0 then "none" else join(", ") end
')
linked_branches=$(printf '%s' "$status_json" | jq -r '
  [.data.repository.issue.linkedBranches.nodes[] |
    "\(.ref.repository.nameWithOwner):\(.ref.name)"] |
  if length == 0 then "none" else join(", ") end
')

if [ "$child_total" -eq 0 ]; then
  child_summary=none
elif [ "$child_loaded" -ne "$child_total" ]; then
  child_summary="$child_loaded of $child_total loaded (truncated)"
else
  closed_children=$(printf '%s' "$status_json" | jq -r '[.data.repository.issue.subIssues.nodes[] | select(.state == "CLOSED")] | length')
  child_summary="$closed_children of $child_total closed"
fi

project_started=false
if project_json=$("$script_directory/project-transition.sh" status "$canonical_repository" "$number"); then
  project_status=$(printf '%s' "$project_json" | jq -r '
    if .status == "disabled" then "disabled"
    elif (.updates | length) == 0 then "no managed assigned fields"
    else [.updates[] | .board + ": " + .field + "=" + (.current // "unset") +
      (if .status == "unchanged" then "" else " (expected " + .expected + ")" end)] | join(", ") end')
  project_started=$(printf '%s' "$project_json" | jq -r 'any(.updates[]; .event == "start" and .status == "unchanged")')
else
  project_status="needs attention: $project_json"
fi

local_worktrees=none
local_started=false
worktree_branches_json='[]'
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  current_remote=$(git remote get-url origin 2>/dev/null || true)
  case "$current_remote" in
    git@github.com:*) current_repository=${current_remote#git@github.com:} ;;
    https://github.com/*) current_repository=${current_remote#https://github.com/} ;;
    ssh://git@github.com/*) current_repository=${current_remote#ssh://git@github.com/} ;;
    *) current_repository= ;;
  esac
  current_repository=${current_repository%.git}

  if [ "$current_repository" = "$canonical_repository" ]; then
    local_matches=$(git worktree list --porcelain | awk -v number="$number" '
      function emit() {
        if (path != "" && branch ~ ("(^|[-_/])" number "([-_/]|$)")) {
          print path " [" branch "]"
        }
      }
      /^worktree / {
        path = substr($0, 10)
        next
      }
      /^branch refs\/heads\// {
        branch = substr($0, 19)
        next
      }
      /^$/ {
        emit()
        path = ""
        branch = ""
      }
      END { emit() }
    ')
    if [ -n "$local_matches" ]; then
      local_started=true
      local_worktrees=$(printf '%s\n' "$local_matches" | paste -sd ',' - | sed 's/,/, /g')
    fi
    worktree_branches_json=$(git worktree list --porcelain |
      awk '/^branch refs\/heads\// { print substr($0, 19) }' |
      jq -Rnc '[inputs | select(length > 0)]')
  fi
fi

if [ "$linked_branch_count" -gt 0 ] || [ "$project_started" = "true" ] || [ "$local_started" = "true" ]; then
  started=yes
else
  started=no
fi

recommendation="none"
recommendation_number=
recommendation_reason="none"
walk_stop=
skipped_started='[]'
walk_query_limit=25
walk_depth_limit=8

# Ready children are open and unblocked. A standalone child with a linked
# branch or a local worktree branch that contains its number is started work.
ready_children_filter='
  def started:
    (.number | tostring) as $issue |
    .linkedBranches.totalCount > 0 or
    any($branches[]; test("(^|[-_/])" + $issue + "([-_/]|$)"));
  [.data.repository.issue.subIssues.nodes[] |
    select(.state == "OPEN") |
    select([.blockedBy.nodes[] | select(.state == "OPEN")] | length == 0) |
    {
      number,
      title,
      depth: $depth,
      compound: (.subIssues.totalCount > 0),
      started: (.subIssues.totalCount == 0 and started)
    }]
'

if [ "$issue_state" = "OPEN" ] && [ "$issue_type" = "compound" ] && [ "$child_loaded" -eq "$child_total" ]; then
  pending=$(printf '%s' "$status_json" | jq -c \
    --argjson depth 1 --argjson branches "$worktree_branches_json" \
    "$ready_children_filter")
  walk_queries=0
  while :; do
    entry=$(printf '%s' "$pending" | jq -c '.[0] // empty')
    [ -n "$entry" ] || break
    pending=$(printf '%s' "$pending" | jq -c '.[1:]')
    entry_number=$(printf '%s' "$entry" | jq -r '.number')

    if [ "$(printf '%s' "$entry" | jq -r '.compound')" = "false" ]; then
      if [ "$(printf '%s' "$entry" | jq -r '.started')" = "true" ]; then
        skipped_started=$(printf '%s' "$skipped_started" | jq -c --argjson entry "$entry" '. + [$entry]')
        continue
      fi
      recommendation_number=$entry_number
      recommendation="#${entry_number} $(printf '%s' "$entry" | jq -r '.title')"
      recommendation_reason="first open unblocked standalone issue with no branch evidence"
      break
    fi

    entry_depth=$(printf '%s' "$entry" | jq -r '.depth')
    if [ "$entry_depth" -ge "$walk_depth_limit" ]; then
      walk_stop="unavailable because the hierarchy below #$entry_number is deeper than $walk_depth_limit levels"
      break
    fi
    if [ "$walk_queries" -ge "$walk_query_limit" ]; then
      walk_stop="unavailable because the walk reached its limit of $walk_query_limit issue queries"
      break
    fi
    walk_queries=$((walk_queries + 1))

    cursor_json=$("$script_directory/query.sh" status "$canonical_repository" "$entry_number")
    cursor_issue=$(printf '%s' "$cursor_json" | jq -r '.data.repository.issue != null')
    [ "$cursor_issue" = "true" ] || {
      walk_stop="unavailable after GitHub returned incomplete hierarchy data"
      break
    }
    cursor_total=$(printf '%s' "$cursor_json" | jq -r '.data.repository.issue.subIssues.totalCount')
    cursor_loaded=$(printf '%s' "$cursor_json" | jq -r '.data.repository.issue.subIssues.nodes | length')
    [ "$cursor_total" -eq "$cursor_loaded" ] || {
      walk_stop="unavailable because GitHub truncated the child list of #$entry_number"
      break
    }
    children=$(printf '%s' "$cursor_json" | jq -c \
      --argjson depth "$((entry_depth + 1))" --argjson branches "$worktree_branches_json" \
      "$ready_children_filter")
    pending=$(jq -nc --argjson children "$children" --argjson pending "$pending" '$children + $pending')
  done

  if [ -n "$walk_stop" ]; then
    recommendation_reason=$walk_stop
  elif [ -z "$recommendation_number" ]; then
    if [ "$(printf '%s' "$skipped_started" | jq 'length')" -gt 0 ]; then
      recommendation_reason="every open unblocked standalone descendant is already started"
    else
      recommendation_reason="no open unblocked standalone descendant"
    fi
  fi
fi

skipped_summary=$(printf '%s' "$skipped_started" | jq -r '
  if length == 0 then "none" else [.[] | "#\(.number) \(.title)"] | join(", ") end
')

if [ "$issue_state" != "OPEN" ]; then
  next_action="none"
elif [ "$active_blocker_count" -gt 0 ]; then
  next_action="resolve the active blocker"
elif [ "$issue_type" = "compound" ]; then
  if [ -n "$recommendation_number" ]; then
    next_action="start issue #$recommendation_number"
  elif [ "$child_loaded" -ne "$child_total" ]; then
    next_action="inspect the truncated child list"
  elif [ -n "$walk_stop" ]; then
    next_action="inspect the descendant hierarchy"
  elif [ "$open_child_count" -gt 0 ]; then
    next_action="continue or unblock the open child work"
  else
    next_action="finish issue #$number"
  fi
elif [ "$started" = "yes" ]; then
  next_action="continue or finish issue #$number"
else
  next_action="start issue #$number"
fi

printf 'Issue: #%s %s\n' "$number" "$issue_title"
printf 'URL: %s\n' "$issue_url"
printf 'State: %s\n' "$issue_state"
printf 'Type: %s\n' "$issue_type"
printf 'Parent: %s\n' "$parent"
printf 'Children: %s\n' "$child_summary"
printf 'Blockers: %s\n' "$blockers"
printf 'Linked branches: %s\n' "$linked_branches"
printf 'Local worktrees: %s\n' "$local_worktrees"
printf 'Project status: %s\n' "$project_status"
printf 'Started: %s\n' "$started"
printf 'Recommendation: %s\n' "$recommendation"
printf 'Recommendation reason: %s\n' "$recommendation_reason"
printf 'Skipped as started: %s\n' "$skipped_summary"
printf 'Next: %s\n' "$next_action"
