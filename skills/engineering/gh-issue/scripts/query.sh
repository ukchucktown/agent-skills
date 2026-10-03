#!/bin/sh
set -eu

usage() {
  echo "usage: query.sh status|start|finish|project-status|clean-root OWNER/REPOSITORY|. ISSUE_NUMBER" >&2
  exit 64
}

[ "$#" -eq 3 ] || usage

mode=$1
repository=$2
number=$3

case "$mode" in
  status|start|finish|project-status|clean-root) ;;
  *) usage ;;
esac

if [ "$repository" = "." ]; then
  remote=$(git remote get-url origin 2>/dev/null) || {
    echo "query.sh: cannot resolve the current repository's origin" >&2
    exit 69
  }
  case "$remote" in
    git@github.com:*) repository=${remote#git@github.com:} ;;
    https://github.com/*) repository=${remote#https://github.com/} ;;
    ssh://git@github.com/*) repository=${remote#ssh://git@github.com/} ;;
    *)
      echo "query.sh: origin is not a github.com repository: $remote" >&2
      exit 69
      ;;
  esac
  repository=${repository%.git}
fi

case "$repository" in
  */*) ;;
  *) usage ;;
esac

owner=${repository%%/*}
name=${repository#*/}
[ -n "$owner" ] && [ -n "$name" ] || usage
case "$name" in
  */*) usage ;;
esac

case "$number" in
  ''|*[!0-9]*) usage ;;
esac
[ "$number" -gt 0 ] || usage

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
query="$script_directory/../references/$mode.graphql"
[ -r "$query" ] || {
  echo "query.sh: missing query: $query" >&2
  exit 66
}

exec gh api graphql \
  -F "owner=$owner" \
  -F "name=$name" \
  -F "number=$number" \
  -F "query=@$query"
