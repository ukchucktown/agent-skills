#!/bin/sh
# Answers the GraphQL queries of clean.sh and cancel.sh from an issue graph.
# GH_ISSUE_GRAPH names a JSON file with the repository, the default branch,
# the open pull requests, and one record for each issue with its parent.
# An issue record without "repository" is in the graph repository. A numeric
# "parent" names an issue in the graph repository; an object parent names
# {"repository", "number"} of an issue in another repository.
set -eu

graph=${GH_ISSUE_GRAPH:?GH_ISSUE_GRAPH is required}
mode=
number=0
after=
text=
for argument in "$@"; do
  case "$argument" in
    query=@*) mode=$(basename "${argument#query=@}" .graphql) ;;
    query=*) mode=scope; text=${argument#query=} ;;
    number=*) number=${argument#number=} ;;
    after=*) after=${argument#after=} ;;
  esac
done
[ -z "${GH_GRAPHQL_LOG:-}" ] ||
  printf '%s\t%s\t%s\n' "$mode" "$number" "$after" >>"$GH_GRAPHQL_LOG"

numbers=$(printf '%s' "$text" | grep -oE 'issue\(number: [0-9]+\)' | grep -oE '[0-9]+' | paste -sd ',' -)

output=$(jq \
  --arg mode "$mode" \
  --argjson number "$number" \
  --arg after "$after" \
  --argjson numbers "[${numbers}]" \
  --argjson size "${GH_PAGE_SIZE:-100}" \
  --argjson truncated "$([ "${GH_TRUNCATED:-false}" = "true" ] && echo 1 || echo 0)" '
  . as $graph |
  def repository_name: .repository // $graph.repository;
  def lookup($repository; $n):
    [$graph.issues[] | select(.number == $n and repository_name == $repository)] | first;
  def issue_record($n): lookup($graph.repository; $n);
  def parent_record:
    if (.parent | type) == "object" then lookup(.parent.repository; .parent.number)
    else issue_record(.parent) end;
  def repository_field: {repository: {nameWithOwner: repository_name}};
  def url($n): "https://github.com/\($graph.repository)/issues/\($n)";
  def linked: {
    totalCount: (.linkedTotal // (.linked | length)),
    nodes: [.linked[] | {ref: {name: ., repository: {nameWithOwner: $graph.repository}}}]
  };
  def root_chain: if .parent == null then null
    else parent_record |
      {number, title, state, url: url(.number)} + repository_field + {parent: root_chain} end;
  def number_chain: if .parent == null then null
    else parent_record | {number} + repository_field + {parent: number_chain} end;
  def children($n): [$graph.issues[] | select(.parent == $n)] | sort_by(.number);
  def clean_issue:
    {number, title, state, url: url(.number)} + repository_field + {linkedBranches: linked};

  if $mode == "clean-root" then
    {data: {repository: {
      nameWithOwner: $graph.repository,
      defaultBranchRef: {name: $graph.defaultBranch},
      issue: (issue_record($number) | if . == null then null
        else {number, title, state, url: url(.number)} + repository_field +
          {parent: root_chain} end)
    }}}
  elif $mode == "clean-repository" then
    {data: {repository: {
      nameWithOwner: $graph.repository,
      defaultBranchRef: {name: $graph.defaultBranch},
      openPullRequests: {
        totalCount: ($graph.openPullRequests | length),
        nodes: [$graph.openPullRequests[] |
          {number, headRefName, url: "https://github.com/\($graph.repository)/pull/\(.number)"}]
      }
    }}}
  elif $mode == "clean-subissues" then
    children($number) as $children |
    (if $after == "" then 0 else ($after | tonumber) end) as $offset |
    $children[$offset:$offset + $size] as $page |
    {data: {repository: {issue: (issue_record($number) | clean_issue + {subIssues: {
      totalCount: (($children | length) + $truncated),
      pageInfo: {
        hasNextPage: ($offset + $size < ($children | length)),
        endCursor: "\($offset + ($page | length))"
      },
      nodes: [$page[] | clean_issue + {subIssues: {totalCount: (children(.number) | length)}}]
    }})}}}
  elif $mode == "scope" then
    {data: {repository: (reduce $numbers[] as $n ({};
      .["i\($n)"] = (issue_record($n) | if . == null then null
        else {number, title, state, linkedBranches: linked, parent: number_chain} end)))}} |
    ([$numbers[] | select(issue_record(.) == null) |
      {type: "NOT_FOUND", path: ["repository", "i\(.)"],
       message: "Could not resolve to an issue with the number of \(.)."}]) as $errors |
    if ($errors | length) > 0 then . + {errors: $errors} else . end
  else
    error("unexpected GraphQL query: \($mode)")
  end
' "$graph")
printf '%s\n' "$output"
# gh exits 1 when GitHub returns errors, but it still prints the response.
! printf '%s' "$output" | jq -e 'has("errors")' >/dev/null
