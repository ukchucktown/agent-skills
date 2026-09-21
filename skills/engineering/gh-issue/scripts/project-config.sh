#!/bin/sh
set -eu

usage() {
  echo "usage: project-config.sh OWNER/REPOSITORY|." >&2
  exit 64
}

[ "$#" -eq 1 ] || usage

repository=$1
if [ "$repository" = "." ]; then
  remote=$(git remote get-url origin 2>/dev/null) || {
    echo "project-config.sh: cannot resolve the current repository's origin" >&2
    exit 69
  }
  case "$remote" in
    git@github.com:*) repository=${remote#git@github.com:} ;;
    https://github.com/*) repository=${remote#https://github.com/} ;;
    ssh://git@github.com/*) repository=${remote#ssh://git@github.com/} ;;
    *)
      echo "project-config.sh: origin is not a github.com repository: $remote" >&2
      exit 69
      ;;
  esac
  repository=${repository%.git}
fi

case "$repository" in
  */*) ;;
  *) usage ;;
esac

command -v jq >/dev/null 2>&1 || {
  echo "project-config.sh: jq is required" >&2
  exit 69
}

config_path=${AGENT_SKILLS_CONFIG:-${HOME}/.config/agent-skills/config.json}
if [ ! -r "$config_path" ]; then
  printf '{"enabled":false,"targeted":false,"owner":null,"number":null,"field":"Status","startOption":"In Progress"}\n'
  exit 0
fi

if ! jq -ce --arg repository "$repository" '
  if type != "object" then error("configuration must be a JSON object") else . end |
  ($repository | split("/")[0]) as $repositoryOwner |
  (.projectStatus // null) as $shared |
  (.repositories[$repository].projectStatus // null) as $override |
  if $shared != null and ($shared | type) != "object" then
    error("projectStatus must be an object")
  elif $override != null and ($override | type) != "object" then
    error("repositories[\($repository)].projectStatus must be an object")
  else . end |
  if (($shared.enabled // false) == true) and
     ((($shared.owner // "") | type) != "string" or
      (($shared.owner // "") | length) == 0 or
      (($shared.number // 0) | type) != "number" or
      ($shared.number | floor) != $shared.number or
      $shared.number <= 0) then
    error("enabled top-level projectStatus requires owner and a positive integer number")
  else . end |
  (($shared | type) == "object" and
   (($shared.owner // "") | ascii_downcase) == ($repositoryOwner | ascii_downcase)) as $sharedApplies |
  (if $sharedApplies then $shared else {} end) as $base |
  (if ($override | type) == "object" then ($base + $override) else $base end) |
  {
    enabled: (.enabled // false),
    owner: (.owner // null),
    number: (.number // null),
    field: (.field // "Status"),
    startOption: (.startOption // "In Progress")
  } |
  .targeted = ((.owner != null) and (.number != null)) |
  if (.enabled | type) != "boolean" then
    error("projectStatus.enabled must be boolean")
  elif (.owner == null) != (.number == null) then
    error("projectStatus.owner and projectStatus.number must be set together")
  elif .number != null and
       ((.number | type) != "number" or (.number | floor) != .number or .number <= 0) then
    error("projectStatus.number must be a positive integer")
  elif (.field | type) != "string" or (.field | length) == 0 then
    error("projectStatus.field must be a non-empty string")
  elif (.startOption | type) != "string" or (.startOption | length) == 0 then
    error("projectStatus.startOption must be a non-empty string")
  else . end
' "$config_path"; then
  echo "project-config.sh: invalid configuration in $config_path" >&2
  exit 65
fi
