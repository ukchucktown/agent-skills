#!/bin/sh
set -eu

usage() {
  echo "usage: start.sh start|resume [--branch BRANCH] [--base BRANCH] [--destination PATH] [--accept-in-use PATH] [--project-override JSON] OWNER/REPOSITORY|. ISSUE_NUMBER" >&2
  exit 64
}

needs_input() {
  field=$1
  question=$2
  candidates_file=${3:-}
  if [ -n "$candidates_file" ] && [ -s "$candidates_file" ]; then
    candidates=$(jq -Rsc 'split("\n") | map(select(length > 0))' "$candidates_file")
  else
    candidates='[]'
  fi
  jq -cn --arg field "$field" --arg question "$question" --argjson candidates "$candidates" \
    '{status:"needs_input", field:$field, question:$question, candidates:$candidates}'
  exit 2
}

# Record every branch name that start can see: local, origin, and worktree branches.
collect_names() {
  {
    git -C "$primary" for-each-ref --format='%(refname:short)' refs/heads refs/remotes/origin | sed 's#^origin/##'
    cut -f2 "$worktree_rows"
  } | awk 'NF' | sort -u >"$names_file"
}

# Classify the branches of every hierarchy issue with the rule that status and finish share.
discover_hierarchy() {
  if ! jq -n --rawfile names "$names_file" --slurpfile issues "$issues_file" \
    '{names: ($names | split("\n") | map(select(length > 0))), issues: $issues[0]}' |
    "$script_directory/branch-discovery.sh" "$canonical_repository" --checkout="$primary" >"$discovery_file"; then
    echo "start.sh: $(jq -r '.message // "branch discovery failed"' "$discovery_file" 2>/dev/null || true)" >&2
    exit 2
  fi
}

discovered() {
  jq -r --argjson number "$1" ".issues[] | select(.number == \$number) | $2" "$discovery_file"
}

branch_known() {
  grep -Fx -- "$1" "$names_file" >/dev/null
}

valid_branch_name() {
  git check-ref-format --branch "$1" >/dev/null 2>&1 || {
    echo "start.sh: $2 is not a valid branch name: $1" >&2
    exit 2
  }
}

# Ask before start ignores a branch that only contains the issue number.
ask_possible() {
  possible_number=$1
  possible_file=$temporary_directory/possible-$possible_number
  discovered "$possible_number" '.possible[]' >"$possible_file"
  [ -s "$possible_file" ] || return 0
  possible_list=$(paste -sd ',' "$possible_file" | sed 's/,/, /g')
  possible_intro="Issue #$possible_number has no linked branch and no branch that fits $(discovered "$possible_number" '.template'). These branches contain the issue number: $possible_list."
  if [ "$possible_number" -ne "$number" ]; then
    needs_input base "$possible_intro Which existing branch should provide the base for issue #$number?" "$possible_file"
  fi
  possible_new=$(discovered "$possible_number" '.rendered // empty')
  if [ -n "$possible_new" ]; then
    printf '%s\n' "$possible_new" >>"$possible_file"
    needs_input branch "$possible_intro Which branch should issue #$number use? Choose $possible_new to create a new branch." "$possible_file"
  fi
  needs_input branch "$possible_intro Which branch should issue #$number use? Name a new branch to create one." "$possible_file"
}

# A template that uses {key} cannot render a branch without a title match.
ask_missing_key() {
  [ "$(discovered "$1" '.missingKey')" = "true" ] || return 0
  missing_intro="The title of issue #$1 does not match branchKey.pattern, so $(discovered "$1" '.template') cannot render {key}."
  if [ "$1" -ne "$number" ]; then
    needs_input base "$missing_intro Which existing branch should provide the base for issue #$number?"
  fi
  needs_input branch "$missing_intro Which branch should issue #$number use? Name a new branch to create one."
}

# Start records the issue of each branch it creates or attaches in this clone.
# A branch recorded for another issue never becomes the branch of this issue.
refuse_recorded() {
  # A record of a branch that no longer exists in this clone is obsolete.
  branch_known "$2" || return 0
  recorded_issue=$(jq -r --arg branch "$2" '.records[$branch] // empty' "$discovery_file")
  if [ -n "$recorded_issue" ] && [ "$recorded_issue" != "$1" ]; then
    echo "start.sh: branch $2 belongs to issue #$recorded_issue in this clone, not issue #$1. Name another branch with --branch." >&2
    exit 2
  fi
}

# A branch that the issue links but the record gives to another issue is a
# conflict. Start shows the conflict and makes no change.
refuse_conflicts() {
  conflict=$(discovered "$1" '.conflicts[0] // empty | "\(.branch)\t\(.issue)"')
  [ -n "$conflict" ] || return 0
  conflict_branch=$(printf '%s' "$conflict" | cut -f1)
  conflict_issue=$(printf '%s' "$conflict" | cut -f2)
  echo "start.sh: issue #$1 links branch $conflict_branch, but this clone records it for issue #$conflict_issue. Resolve the conflict first. If issue #$conflict_issue no longer owns the branch, remove the record: git config --unset branch.$conflict_branch.gh-issue" >&2
  exit 2
}

record_branch() {
  git -C "$primary" config "branch.$2.gh-issue" "$1"
}

# Refuse a rendered name that belongs to another issue, and ask before start
# uses an existing shared name that no link or record ties to the issue.
check_rendered() {
  rendered_number=$1
  rendered_name=$(discovered "$rendered_number" '.rendered // empty')
  if [ -n "$rendered_name" ]; then
    refuse_recorded "$rendered_number" "$rendered_name"
  fi
  unverified_file=$temporary_directory/unverified-$rendered_number
  discovered "$rendered_number" '.unverified[]' >"$unverified_file"
  [ -s "$unverified_file" ] || return 0
  unverified_intro="Branch $(sed -n '1p' "$unverified_file") exists, but issue #$rendered_number has no link to it and this clone has no record of its issue. Another open issue can own it."
  if [ "$rendered_number" -ne "$number" ]; then
    needs_input base "$unverified_intro Which existing branch should provide the base for issue #$number?" "$unverified_file"
  fi
  needs_input branch "$unverified_intro Which branch should issue #$number use? Choose it only when it belongs to this issue, or name a new branch." "$unverified_file"
}

# Print the branch of the checkout whose top level is the given path.
destination_occupant() {
  occupant_top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ "$(CDPATH= cd -- "$1" && pwd -P)" = "$(CDPATH= cd -- "$occupant_top" && pwd -P)" ] || return 1
  occupant_branch=$(git -C "$1" branch --show-current 2>/dev/null || true)
  if [ -n "$occupant_branch" ]; then printf 'branch %s\n' "$occupant_branch"; else printf 'a detached HEAD\n'; fi
}

resolve_destination() {
  if [ -n "$selected_destination" ]; then
    destination=$selected_destination
  else
    path_output=$temporary_directory/path.json
    if ! "$script_directory/worktree-path.sh" "$canonical_repository" --checkout="$primary" \
      --number="$number" --title="$issue_title" --branch="$1" >"$path_output"; then
      if jq -e '.status == "needs_input"' "$path_output" >/dev/null 2>&1; then
        needs_input destination "$(jq -r '.message' "$path_output")"
      fi
      echo "start.sh: $(jq -r '.message // "cannot render the worktree path"' "$path_output" 2>/dev/null || true)" >&2
      exit 2
    fi
    destination=$(jq -r '.path' "$path_output")
  fi
  worktree_location=$(dirname -- "$destination")
  if [ -n "$existing_worktree" ] || [ ! -e "$destination" ]; then
    return 0
  fi
  if occupant=$(destination_occupant "$destination"); then
    echo "start.sh: destination $destination already holds a worktree on $occupant" >&2
    exit 2
  fi
  printf '%s\n' "$destination" >"$temporary_directory/destination"
  needs_input destination "Which unused destination should issue #$number use?" "$temporary_directory/destination"
}

worktree_for_branch() {
  awk -F '\t' -v branch="$1" '$2 == branch { print $1 }' "$worktree_rows"
}

branch_exists_locally() {
  git -C "$primary" show-ref --verify --quiet "refs/heads/$1"
}

branch_exists_remotely() {
  git -C "$primary" show-ref --verify --quiet "refs/remotes/origin/$1"
}

branch_reference() {
  if branch_exists_remotely "$1"; then
    printf 'refs/remotes/origin/%s\n' "$1"
  elif branch_exists_locally "$1"; then
    printf 'refs/heads/%s\n' "$1"
  else
    echo "start.sh: base branch $1 is unavailable" >&2
    return 2
  fi
}

assign_issue() {
  assignee_count=$(jq -r '.data.repository.issue.assignees.totalCount' "$issue_json")
  assignee_loaded=$(jq -r '.data.repository.issue.assignees.nodes | length' "$issue_json")
  [ "$assignee_count" = "$assignee_loaded" ] || {
    echo "start.sh: GitHub truncated issue assignees" >&2
    return 2
  }
  if [ "$assignee_count" -eq 0 ]; then
    assignee=$(gh api user --jq '.login')
    [ -n "$assignee" ] || return 2
    gh issue edit "$number" --repo "$canonical_repository" --add-assignee "$assignee" >/dev/null
    assignment="$assignee (assigned)"
  else
    assignment="$(jq -r '.data.repository.issue.assignees.nodes | map(.login) | join(", ")' "$issue_json") (preserved)"
  fi
}

[ "$#" -ge 1 ] || usage
mode=$1
shift
case "$mode" in
  start|resume) ;;
  *) usage ;;
esac

selected_branch=
selected_base=
selected_destination=
accepted_in_use=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch|--base|--destination|--accept-in-use|--project-override)
      [ "$#" -ge 2 ] || usage
      case "$1" in
        --branch) selected_branch=$2 ;;
        --base) selected_base=$2 ;;
        --destination) selected_destination=$2 ;;
        --accept-in-use) accepted_in_use=$2 ;;
        --project-override) AGENT_SKILLS_PROJECT_OVERRIDE=$2; export AGENT_SKILLS_PROJECT_OVERRIDE ;;
      esac
      shift 2
      ;;
    --) shift; break ;;
    -*) usage ;;
    *) break ;;
  esac
done

[ "$#" -eq 2 ] || usage
repository=$1
number=$2
case "$number" in
  ''|*[!0-9]*) usage ;;
esac
[ "$number" -gt 0 ] || usage

command -v jq >/dev/null 2>&1 || {
  echo "start.sh: jq is required" >&2
  exit 69
}
command -v git >/dev/null 2>&1 || {
  echo "start.sh: git is required" >&2
  exit 69
}

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/gh-issue-start.XXXXXX")
trap 'find "$temporary_directory" -type f -delete 2>/dev/null || true; rmdir "$temporary_directory" 2>/dev/null || true' EXIT HUP INT TERM

issue_json=$temporary_directory/issue.json
if ! "$script_directory/query.sh" start "$repository" "$number" >"$issue_json"; then
  echo "start.sh: cannot read issue #$number" >&2
  exit 2
fi

issue_exists=$(jq -r '.data.repository.issue != null' "$issue_json")
[ "$issue_exists" = "true" ] || {
  echo "start.sh: issue #$number was not found" >&2
  exit 2
}

canonical_repository=$(jq -er '.data.repository.nameWithOwner' "$issue_json")
default_branch=$(jq -er '.data.repository.defaultBranchRef.name' "$issue_json")
focused_state=$(jq -r '.data.repository.issue.state' "$issue_json")
[ "$focused_state" = "OPEN" ] || {
  echo "start.sh: issue #$number is $focused_state" >&2
  exit 2
}

hierarchy_file=$temporary_directory/hierarchy.json
if ! jq -ce '
  def hierarchy:
    [.] + (if (.parent? | type) == "object" then (.parent | hierarchy) else [] end);
  (.data.repository.issue | hierarchy) as $hierarchy |
  if any($hierarchy[]; .state != "OPEN") then
    error("the issue hierarchy contains a closed issue")
  elif any($hierarchy[]; .linkedBranches.totalCount > (.linkedBranches.nodes | length)) then
    error("GitHub truncated linked branches")
  elif ($hierarchy[-1].parent? | type) == "object" then
    error("GitHub truncated the ancestor hierarchy")
  else $hierarchy end
' "$issue_json" >"$hierarchy_file"; then
  echo "start.sh: issue hierarchy is closed or incomplete" >&2
  exit 2
fi

current_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "start.sh: run this command from a checkout of $canonical_repository" >&2
  exit 69
}
git -C "$current_root" worktree list --porcelain >"$temporary_directory/worktrees"
primary=$(awk '/^worktree / { print substr($0, 10); exit }' "$temporary_directory/worktrees")
[ -n "$primary" ] || {
  echo "start.sh: cannot resolve the primary checkout" >&2
  exit 69
}

local_repository=$(git -C "$primary" config --get remote.origin.url 2>/dev/null || true)
case "$local_repository" in
  git@github.com:*) local_repository=${local_repository#git@github.com:} ;;
  https://github.com/*) local_repository=${local_repository#https://github.com/} ;;
  ssh://git@github.com/*) local_repository=${local_repository#ssh://git@github.com/} ;;
  *) local_repository= ;;
esac
local_repository=${local_repository%.git}
if [ -z "$local_repository" ] || [ "$(printf '%s' "$local_repository" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "$canonical_repository" | tr '[:upper:]' '[:lower:]')" ]; then
  echo "start.sh: current checkout is not $canonical_repository" >&2
  exit 69
fi

worktree_rows=$temporary_directory/worktree-rows
awk '
  function emit() {
    if (path != "" && branch != "") print path "\t" branch
  }
  /^worktree / { emit(); path = substr($0, 10); branch = ""; next }
  /^branch refs\/heads\// { branch = substr($0, 19); next }
  END { emit() }
' "$temporary_directory/worktrees" >"$worktree_rows"

if ! config=$("$script_directory/start-config.sh" "$canonical_repository" --checkout="$primary"); then
  echo "start.sh: $(printf '%s' "$config" | jq -r '.message // "cannot resolve the configuration"' 2>/dev/null || true)" >&2
  exit 2
fi
configured_base=$(printf '%s' "$config" | jq -r '.taskBaseBranch // empty')
if [ -z "$selected_base" ] && [ "$(jq -r '.[0].subIssues.totalCount // 0' "$hierarchy_file")" -eq 0 ]; then
  selected_base=$configured_base
fi
if [ -n "$selected_base" ]; then
  git check-ref-format "refs/heads/$selected_base" >/dev/null || {
    echo "start.sh: invalid base branch $selected_base" >&2
    exit 2
  }
fi

names_file=$temporary_directory/names
issues_file=$temporary_directory/issues.json
discovery_file=$temporary_directory/discovery.json
# Ancestors always use the integration template. The focused issue uses it only with children.
jq -c --arg repository "$canonical_repository" '
  [to_entries[] | .key as $index | .value | {
    number,
    title,
    compound: (if $index == 0 then (.subIssues.totalCount // 0) > 0 else true end),
    linked: [.linkedBranches.nodes[]? |
      select((.ref.repository.nameWithOwner | ascii_downcase) == ($repository | ascii_downcase)) | .ref.name]
  }]' "$hierarchy_file" >"$issues_file"
collect_names
discover_hierarchy

focused_candidates=$temporary_directory/focused-candidates
discovered "$number" '.matches[]' >"$focused_candidates"
focused_candidate_count=$(wc -l <"$focused_candidates" | tr -d ' ')
focused_branch=
planned_branch=
refuse_conflicts "$number"
if [ -n "$selected_branch" ]; then
  if [ "$focused_candidate_count" -gt 0 ] && ! grep -Fx -- "$selected_branch" "$focused_candidates" >/dev/null; then
    needs_input branch "Which existing branch should issue #$number use?" "$focused_candidates"
  fi
  refuse_recorded "$number" "$selected_branch"
  if branch_known "$selected_branch"; then
    focused_branch=$selected_branch
  else
    # An explicit name that does not exist yet selects a new branch.
    valid_branch_name "$selected_branch" "The selected branch"
    planned_branch=$selected_branch
  fi
elif [ "$focused_candidate_count" -eq 1 ]; then
  focused_branch=$(sed -n '1p' "$focused_candidates")
elif [ "$focused_candidate_count" -gt 1 ]; then
  needs_input branch "Which existing branch should issue #$number use?" "$focused_candidates"
else
  check_rendered "$number"
  ask_possible "$number"
  ask_missing_key "$number"
  planned_branch=$(discovered "$number" '.rendered')
  valid_branch_name "$planned_branch" "$(discovered "$number" '.template')"
fi

existing_worktree=
if [ -n "$focused_branch" ]; then
  existing_worktree=$(worktree_for_branch "$focused_branch")
  existing_worktree_count=$(printf '%s\n' "$existing_worktree" | awk 'NF { count++ } END { print count + 0 }')
  if [ "$existing_worktree_count" -gt 1 ]; then
    printf '%s\n' "$existing_worktree" >"$temporary_directory/conflicting-worktrees"
    if [ -n "$selected_destination" ] && grep -Fx "$selected_destination" "$temporary_directory/conflicting-worktrees" >/dev/null; then
      existing_worktree=$selected_destination
    else
      needs_input destination "Which worktree should issue #$number use?" "$temporary_directory/conflicting-worktrees"
    fi
  fi
fi

issue_title=$(jq -r '.[0].title' "$hierarchy_file")
destination=
if [ -z "$existing_worktree" ]; then
  resolve_destination "${focused_branch:-$planned_branch}"
fi

project_output=$temporary_directory/project-output
if ! "$script_directory/project-start.sh" --dry-run "$canonical_repository" "$number" >"$project_output"; then
  cat "$project_output"
  exit 2
fi

render_projects() {
  jq -r '
    "Project status synchronization: " + .status,
    (.updates[] | "Project " + .board + " issue #" + (.issue | tostring) + ": " + .field + " → " + .expected + " [" + .status + "]")
  ' "$project_output"
}

apply_projects() {
  if ! "$script_directory/project-start.sh" "$canonical_repository" "$number" >"$project_output"; then
    cat "$project_output"
    exit 2
  fi
}

hierarchy_text=$(jq -r 'reverse | map("#" + (.number | tostring) + " " + .title) | join(" > ")' "$hierarchy_file")
if [ -n "$existing_worktree" ]; then
  if [ "$(git -C "$existing_worktree" branch --show-current 2>/dev/null || true)" != "$focused_branch" ]; then
    echo "start.sh: existing worktree verification failed for $existing_worktree" >&2
    exit 2
  fi
  # Another session can work in the same worktree. Ask before attaching it.
  if ! evidence=$("$script_directory/worktree-evidence.sh" "$existing_worktree" "$focused_branch"); then
    echo "start.sh: worktree evidence failed for $existing_worktree" >&2
    exit 2
  fi
  if printf '%s' "$evidence" | jq -e '.uncommitted > 0' >/dev/null &&
    [ "${accepted_in_use%/}" != "${existing_worktree%/}" ]; then
    printf '%s\n' "$existing_worktree" >"$temporary_directory/in-use"
    needs_input accept-in-use "Worktree $existing_worktree for issue #$number looks in use: $(printf '%s' "$evidence" | jq -r '.summary'). Another session can work in it. Attach it anyway?" "$temporary_directory/in-use"
  fi
  apply_projects
  assign_issue
  record_branch "$number" "$focused_branch"
  printf 'Assignees: %s\n' "$assignment"
  printf 'Status: existing_worktree\n'
  printf 'Repository: %s\n' "$canonical_repository"
  printf 'Issue: #%s %s\n' "$number" "$issue_title"
  printf 'Hierarchy: %s\n' "$hierarchy_text"
  printf 'Branch: %s\n' "$focused_branch"
  printf 'Worktree: %s\n' "$existing_worktree"
  render_projects
  exit 0
fi

if [ -n "$focused_branch" ] && [ "$mode" = "start" ]; then
  assign_issue
  record_branch "$number" "$focused_branch"
  printf 'Assignees: %s\n' "$assignment"
  printf 'Status: already_started\n'
  printf 'Repository: %s\n' "$canonical_repository"
  printf 'Issue: #%s %s\n' "$number" "$issue_title"
  printf 'Hierarchy: %s\n' "$hierarchy_text"
  printf 'Branch: %s\n' "$focused_branch"
  printf 'Worktree: none\n'
  render_projects
  if [ -n "$selected_branch" ]; then
    printf 'Next: resume issue #%s with --branch %s to attach its existing branch.\n' "$number" "$selected_branch"
  else
    printf 'Next: resume issue #%s to attach its existing branch.\n' "$number"
  fi
  exit 0
fi

creation_plan=$temporary_directory/creation-plan
: >"$creation_plan"
if [ -z "$focused_branch" ]; then
  git -C "$primary" fetch origin
  # The fetch can reveal branches that discovery must see before any creation.
  collect_names
  discover_hierarchy
  previous_branch=${selected_base:-$default_branch}
  previous_ref=$(branch_reference "$previous_branch")
  comparison_branch=$previous_branch
  if [ -z "$selected_base" ]; then
    jq -r 'reverse[] | .number' "$hierarchy_file" >"$temporary_directory/hierarchy-lines"
  else
    jq -r '.[0].number' "$hierarchy_file" >"$temporary_directory/hierarchy-lines"
  fi

  while IFS= read -r item_number; do
    refuse_conflicts "$item_number"
    item_candidates=$temporary_directory/candidates-$item_number
    discovered "$item_number" '.matches[]' >"$item_candidates"
    item_candidate_count=$(wc -l <"$item_candidates" | tr -d ' ')

    if [ "$item_number" -eq "$number" ] && [ -n "$selected_branch" ]; then
      item_branch=$selected_branch
      if ! branch_known "$item_branch"; then
        printf '%s\t%s\t%s\n' "$item_number" "$item_branch" "$previous_branch" >>"$creation_plan"
      fi
    elif [ "$item_candidate_count" -eq 1 ]; then
      item_branch=$(sed -n '1p' "$item_candidates")
    elif [ "$item_candidate_count" -gt 1 ]; then
      needs_input base "Which existing branch should provide the base for issue #$number?" "$item_candidates"
    else
      check_rendered "$item_number"
      ask_possible "$item_number"
      ask_missing_key "$item_number"
      item_branch=$(discovered "$item_number" '.rendered')
      valid_branch_name "$item_branch" "$(discovered "$item_number" '.template')"
      printf '%s\t%s\t%s\n' "$item_number" "$item_branch" "$previous_branch" >>"$creation_plan"
    fi
    if [ "$item_candidate_count" -eq 1 ] && [ "$item_number" -ne "$number" ]; then
      item_ref=$(branch_reference "$item_branch")
      missing=$(git -C "$primary" rev-list --count "$item_ref..$previous_ref")
      if [ "$missing" -gt 0 ]; then
        printf '%s\n%s\n' "$comparison_branch" "$item_branch" >"$temporary_directory/stale-bases"
        needs_input base "Ancestor branch $item_branch is missing $missing commit(s) from $comparison_branch. Which base should issue #$number use?" "$temporary_directory/stale-bases"
      fi
      previous_ref=$item_ref
      comparison_branch=$item_branch
    fi
    previous_branch=$item_branch
    if [ "$item_number" -eq "$number" ]; then focused_branch=$item_branch; fi
  done <"$temporary_directory/hierarchy-lines"

  # A branch that appeared in the fetch can change a destination that uses {branch}.
  if [ "$focused_branch" != "$planned_branch" ]; then
    resolve_destination "$focused_branch"
  fi
fi

while IFS="$(printf '\t')" read -r item_number item_branch item_base; do
  [ -n "$item_number" ] || continue
  gh issue develop "$item_number" --repo "$canonical_repository" --base "$item_base" --name "$item_branch" >/dev/null
  record_branch "$item_number" "$item_branch"
done <"$creation_plan"

if [ -s "$creation_plan" ] || ! branch_exists_locally "$focused_branch"; then
  git -C "$primary" fetch origin
fi

if branch_exists_locally "$focused_branch"; then
  attach_kind=local
elif branch_exists_remotely "$focused_branch"; then
  attach_kind=remote
else
  echo "start.sh: branch $focused_branch is unavailable after creation" >&2
  exit 2
fi

mkdir -p "$worktree_location"
if [ "$attach_kind" = "local" ]; then
  git -C "$primary" worktree add "$destination" "$focused_branch" >/dev/null
else
  git -C "$primary" worktree add -b "$focused_branch" --track "$destination" "origin/$focused_branch" >/dev/null
fi

checked_out_branch=$(git -C "$destination" branch --show-current 2>/dev/null || true)
[ "$checked_out_branch" = "$focused_branch" ] || {
  echo "start.sh: worktree verification failed for $destination" >&2
  exit 2
}

assign_issue
record_branch "$number" "$focused_branch"
apply_projects
if [ "$mode" = "resume" ]; then result=resumed; else result=started; fi
printf 'Status: %s\n' "$result"
printf 'Repository: %s\n' "$canonical_repository"
printf 'Issue: #%s %s\n' "$number" "$issue_title"
printf 'Hierarchy: %s\n' "$hierarchy_text"
printf 'Branch: %s\n' "$focused_branch"
printf 'Worktree: %s\n' "$destination"
printf 'Assignees: %s\n' "$assignment"
printf 'Manager: git\n'
render_projects
