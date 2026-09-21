#!/bin/sh
set -eu

usage() {
  echo "usage: project-start.sh [--dry-run] OWNER/REPOSITORY|. ISSUE_NUMBER" >&2
  exit 64
}

dry_run=false
if [ "${1:-}" = "--dry-run" ]; then
  dry_run=true
  shift
fi

[ "$#" -eq 2 ] || usage

repository=$1
number=$2
case "$number" in
  ''|*[!0-9]*) usage ;;
esac
[ "$number" -gt 0 ] || usage

command -v jq >/dev/null 2>&1 || {
  echo "project-start.sh: jq is required" >&2
  exit 69
}

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_config=$(
  "$script_directory/project-config.sh" "$repository"
)

project_enabled=$(printf '%s' "$project_config" | jq -r '.enabled')
if [ "$project_enabled" != "true" ]; then
  printf 'Project status synchronization: disabled\n'
  exit 0
fi

if ! project_json=$("$script_directory/query.sh" project-status "$repository" "$number" 2>&1); then
  printf 'project-start.sh: cannot read Project status. Run gh auth refresh -s read:project,project if the required scopes are missing.\n%s\n' "$project_json" >&2
  exit 2
fi

issue_exists=$(printf '%s' "$project_json" | jq -r '.data.repository.issue != null')
[ "$issue_exists" = "true" ] || {
  echo "project-start.sh: issue #$number was not found" >&2
  exit 2
}

canonical_repository=$(printf '%s' "$project_json" | jq -er '.data.repository.nameWithOwner')
focused_state=$(printf '%s' "$project_json" | jq -r '.data.repository.issue.state')
[ "$focused_state" = "OPEN" ] || {
  echo "project-start.sh: issue #$number is $focused_state" >&2
  exit 2
}

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/gh-issue-project.XXXXXX")
trap 'find "$temporary_directory" -type f -delete 2>/dev/null || true; rmdir "$temporary_directory" 2>/dev/null || true' EXIT HUP INT TERM

targets_file=$temporary_directory/targets.json
if ! printf '%s' "$project_json" | jq -ce '
  def hierarchy:
    [.] + (if (.parent? | type) == "object" then (.parent | hierarchy) else [] end);
  (.data.repository.issue | hierarchy) as $hierarchy |
  if any($hierarchy[]; (.url // "") == "") then
    error("GitHub truncated the ancestor hierarchy")
  elif any($hierarchy[]; .projectItems.totalCount > (.projectItems.nodes | length)) then
    error("GitHub truncated a Project item list")
  elif any($hierarchy[].projectItems.nodes[];
    .project.fields.totalCount > (.project.fields.nodes | length) or
    .fieldValues.totalCount > (.fieldValues.nodes | length)) then
    error("GitHub truncated Project field data")
  else
    [$hierarchy[] | select(.state == "OPEN")]
  end
' >"$targets_file"; then
  echo "project-start.sh: GitHub returned incomplete hierarchy or Project data" >&2
  exit 2
fi

project_owner=$(printf '%s' "$project_config" | jq -r '.owner // empty')
project_number=$(printf '%s' "$project_config" | jq -r '.number // empty')
project_field=$(printf '%s' "$project_config" | jq -r '.field')
project_start_option=$(printf '%s' "$project_config" | jq -r '.startOption')
targeted=$(printf '%s' "$project_config" | jq -r '.targeted')

add_file=$temporary_directory/add
update_file=$temporary_directory/update
: >"$add_file"
: >"$update_file"

if [ "$targeted" = "true" ]; then
  if ! fields_json=$(gh project field-list "$project_number" --owner "$project_owner" --format json 2>&1); then
    printf 'project-start.sh: cannot read %s Project %s. Run gh auth refresh -s read:project,project if the required scopes are missing.\n%s\n' "$project_owner" "$project_number" "$fields_json" >&2
    exit 2
  fi

  fields_total=$(printf '%s' "$fields_json" | jq -r '.totalCount')
  fields_loaded=$(printf '%s' "$fields_json" | jq -r '.fields | length')
  [ "$fields_total" -eq "$fields_loaded" ] || {
    echo "project-start.sh: GitHub returned $fields_loaded of $fields_total Project fields" >&2
    exit 2
  }

  field_count=$(printf '%s' "$fields_json" | jq -r --arg field "$project_field" '[.fields[] | select(.name == $field)] | length')
  [ "$field_count" -eq 1 ] || {
    echo "project-start.sh: expected one '$project_field' field in $project_owner Project $project_number; found $field_count" >&2
    exit 2
  }
  option_count=$(printf '%s' "$fields_json" | jq -r --arg field "$project_field" --arg option "$project_start_option" '
    [.fields[] | select(.name == $field) | .options[]? | select(.name == $option)] | length
  ')
  [ "$option_count" -eq 1 ] || {
    echo "project-start.sh: expected one '$project_start_option' option in field '$project_field'; found $option_count" >&2
    exit 2
  }

  focused_started=$(jq -r --arg owner "$project_owner" --argjson number "$project_number" --arg field "$project_field" --arg option "$project_start_option" '
    .[0] |
    any(.projectItems.nodes[];
      (.project.number == $number) and
      ((.project.owner.login | ascii_downcase) == ($owner | ascii_downcase)) and
      any(.fieldValues.nodes[]; .field.name == $field and .name == $option))
  ' "$targets_file")

  jq -r --arg owner "$project_owner" --argjson number "$project_number" '
    .[] |
    select([.projectItems.nodes[] |
      select(.project.number == $number and
             ((.project.owner.login | ascii_downcase) == ($owner | ascii_downcase)))] | length == 0) |
    .url
  ' "$targets_file" >"$add_file"

  jq -r --arg owner "$project_owner" --argjson number "$project_number" --arg field "$project_field" --arg option "$project_start_option" '
    .[] |
    select(any(.projectItems.nodes[];
      (.project.number == $number) and
      ((.project.owner.login | ascii_downcase) == ($owner | ascii_downcase)) and
      any(.fieldValues.nodes[]; .field.name == $field and .name == $option)) | not) |
    .url
  ' "$targets_file" >"$update_file"
else
  focused_started=$(jq -r --arg field "$project_field" --arg option "$project_start_option" '
    .[0] | any(.projectItems.nodes[].fieldValues.nodes[];
      .field.name == $field and .name == $option)
  ' "$targets_file")

  if ! jq -er --arg field "$project_field" --arg option "$project_start_option" '
    all(.[].projectItems.nodes[];
      ([.project.fields.nodes[] | select(.name == $field)] | length) == 1 and
      ([.project.fields.nodes[] | select(.name == $field) | .options[]? | select(.name == $option)] | length) == 1)
  ' "$targets_file" >/dev/null; then
    echo "project-start.sh: a configured Project has a missing or duplicated field or option" >&2
    exit 2
  fi

  jq -r --arg field "$project_field" --arg option "$project_start_option" '
    .[] as $issue |
    $issue.projectItems.nodes[] |
    select(any(.project.fields.nodes[];
      .name == $field and any(.options[]?; .name == $option))) |
    select(any(.fieldValues.nodes[]; .field.name == $field and .name == $option) | not) |
    [.project.owner.login, (.project.number | tostring), $issue.url] | @tsv
  ' "$targets_file" >"$update_file"
fi

add_count=$(wc -l <"$add_file" | tr -d ' ')
update_count=$(wc -l <"$update_file" | tr -d ' ')

if [ "$dry_run" != "true" ]; then
  while IFS= read -r issue_url; do
    [ -n "$issue_url" ] || continue
    gh project item-add "$project_number" --owner "$project_owner" --url "$issue_url" >/dev/null
  done <"$add_file"

  if [ "$targeted" = "true" ]; then
    while IFS= read -r issue_url; do
      [ -n "$issue_url" ] || continue
      gh project item-edit "$project_number" --owner "$project_owner" --url "$issue_url" --field "$project_field" --value "$project_start_option" >/dev/null
    done <"$update_file"
  else
    while IFS="$(printf '\t')" read -r owner project issue_url; do
      [ -n "$issue_url" ] || continue
      gh project item-edit "$project" --owner "$owner" --url "$issue_url" --field "$project_field" --value "$project_start_option" >/dev/null
    done <"$update_file"
  fi
fi

printf 'Project status synchronization: enabled\n'
printf 'Repository: %s\n' "$canonical_repository"
printf 'Focused issue was already %s: %s\n' "$project_start_option" "$focused_started"
printf 'Project items %s: %s\n' "$([ "$dry_run" = "true" ] && printf 'to add' || printf 'added')" "$add_count"
printf 'Project statuses %s: %s\n' "$([ "$dry_run" = "true" ] && printf 'to update' || printf 'updated')" "$update_count"
