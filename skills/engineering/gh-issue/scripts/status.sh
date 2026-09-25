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
  fi
fi

if [ "$linked_branch_count" -gt 0 ] || [ "$project_started" = "true" ] || [ "$local_started" = "true" ]; then
  started=yes
else
  started=no
fi

recommendation="none"
recommendation_reason="none"
recommended_started=false

if [ "$issue_state" = "OPEN" ] && [ "$issue_type" = "compound" ] && [ "$child_loaded" -eq "$child_total" ]; then
  cursor_json=$status_json
  depth=0
  while [ "$depth" -lt 8 ]; do
    candidate=$(printf '%s' "$cursor_json" | jq -c '
      [.data.repository.issue.subIssues.nodes[] |
        select(.state == "OPEN") |
        select([.blockedBy.nodes[] | select(.state == "OPEN")] | length == 0)] as $ready |
      ([$ready[] | select(.subIssues.totalCount == 0 and .linkedBranches.totalCount > 0)][0] // $ready[0] // null)
    ')
    if [ "$candidate" = "null" ]; then
      if [ "$depth" -gt 0 ]; then
        recommendation=none
        recommendation_reason="no open unblocked standalone descendant"
        recommended_started=false
      fi
      break
    fi

    recommendation_number=$(printf '%s' "$candidate" | jq -r '.number')
    recommendation_title=$(printf '%s' "$candidate" | jq -r '.title')
    recommendation="#${recommendation_number} ${recommendation_title}"
    if [ "$(printf '%s' "$candidate" | jq -r '.linkedBranches.totalCount')" -gt 0 ]; then
      recommended_started=true
      recommendation_reason="already started and unblocked"
    else
      recommended_started=false
      recommendation_reason="first open unblocked child"
    fi

    candidate_children=$(printf '%s' "$candidate" | jq -r '.subIssues.totalCount')
    [ "$candidate_children" -gt 0 ] || break

    cursor_json=$("$script_directory/query.sh" status "$canonical_repository" "$recommendation_number")
    cursor_issue=$(printf '%s' "$cursor_json" | jq -r '.data.repository.issue != null')
    [ "$cursor_issue" = "true" ] || {
      recommendation_reason="unavailable after GitHub returned incomplete hierarchy data"
      break
    }
    cursor_total=$(printf '%s' "$cursor_json" | jq -r '.data.repository.issue.subIssues.totalCount')
    cursor_loaded=$(printf '%s' "$cursor_json" | jq -r '.data.repository.issue.subIssues.nodes | length')
    [ "$cursor_total" -eq "$cursor_loaded" ] || {
      recommendation_reason="unavailable because GitHub truncated the child list"
      break
    }
    depth=$((depth + 1))
  done
fi

if [ "$issue_state" != "OPEN" ]; then
  next_action="none"
elif [ "$active_blocker_count" -gt 0 ]; then
  next_action="resolve the active blocker"
elif [ "$issue_type" = "compound" ]; then
  if [ "$recommendation" != "none" ]; then
    if [ "$recommended_started" = "true" ]; then
      next_action="continue issue #$recommendation_number"
    else
      next_action="start issue #$recommendation_number"
    fi
  elif [ "$child_loaded" -ne "$child_total" ]; then
    next_action="inspect the truncated child list"
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
printf 'Next: %s\n' "$next_action"
