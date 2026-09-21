#!/bin/sh
set -eu

usage() {
  echo "usage: query.sh status|start OWNER/REPOSITORY ISSUE_NUMBER" >&2
  exit 64
}

[ "$#" -eq 3 ] || usage

mode=$1
repository=$2
number=$3

case "$mode" in
  status|start) ;;
  *) usage ;;
esac

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
