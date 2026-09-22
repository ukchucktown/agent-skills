#!/bin/sh
set -eu

usage() {
  echo "usage: start-config.sh OWNER/REPOSITORY" >&2
  exit 64
}

[ "$#" -eq 1 ] || usage
repository=$1

case "$repository" in
  */*) ;;
  *) usage ;;
esac

command -v jq >/dev/null 2>&1 || {
  echo "start-config.sh: jq is required" >&2
  exit 69
}

config_path=${AGENT_SKILLS_CONFIG:-${HOME}/.config/agent-skills/config.json}
if [ ! -r "$config_path" ]; then
  printf '%s\n' '{"worktreeManager":"auto","worktreeRoot":null,"integrationBranchTemplate":"integration/issue-{number}-{slug}","taskBranchTemplate":"feat/issue-{number}-{slug}","worktreeTemplate":"issue-{number}-{slug}"}'
  exit 0
fi

if ! jq -ce --arg repository "$repository" '
  if type != "object" then error("configuration must be a JSON object") else . end |
  (.repositories[$repository] // {}) as $override |
  if ($override | type) != "object" then
    error("repositories[\($repository)] must be an object")
  else . end |
  {
    worktreeManager: ($override.worktreeManager // .worktreeManager // "auto"),
    worktreeRoot: ($override.worktreeRoot // .worktreeRoot // null),
    integrationBranchTemplate: ($override.integrationBranchTemplate // .integrationBranchTemplate // "integration/issue-{number}-{slug}"),
    taskBranchTemplate: ($override.taskBranchTemplate // .taskBranchTemplate // "feat/issue-{number}-{slug}"),
    worktreeTemplate: ($override.worktreeTemplate // .worktreeTemplate // "issue-{number}-{slug}")
  } |
  .worktreeManager as $manager |
  if (["auto", "supacode", "git"] | index($manager)) == null then
    error("worktreeManager must be auto, supacode, or git")
  elif .worktreeRoot != null and ((.worktreeRoot | type) != "string" or (.worktreeRoot | startswith("/") | not)) then
    error("worktreeRoot must be an absolute path")
  elif any([.integrationBranchTemplate, .taskBranchTemplate, .worktreeTemplate][];
    (type != "string") or (contains("{number}") | not) or (contains("{slug}") | not)) then
    error("branch and worktree templates must contain {number} and {slug}")
  else . end
' "$config_path"; then
  echo "start-config.sh: invalid configuration in $config_path" >&2
  exit 65
fi
