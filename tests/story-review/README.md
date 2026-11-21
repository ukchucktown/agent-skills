# story-review tests

Two checks. Neither one reads or changes anything outside this repository.

## Structure and coverage

```text
./tests/story-review/run.sh
```

Deterministic. It confirms that every fixture story has an expectation, that
every expectation names real criteria, and that every criterion has a fixture
that must trigger it. It also passes deliberately wrong results to the grader
and confirms that the grader rejects them. Run it after any change to
`criteria.md`, the fixtures, or `grade.py`.

## Behavior

The skill is a set of instructions for an agent, so a behavior test needs an
agent to follow them.

1. Give a fresh agent the skill folder and the stories in `fixtures/stories/`.
   Do not show it `fixtures/expected.json`. Story `22-later-epic` uses horizon
   `later`. Story `23-checklist` uses `fixtures/checklist.md`. Stories
   `27-checklist-blocking` and `28-checklist-minor` use
   `fixtures/checklist-severity.md`. Tell the agent that nobody can supply a
   document that it cannot open, so that story `26-unread-link` tests the
   report and not the request for access.
2. Have the agent write the full report for each story, and then one JSON line
   for each story, in the shape that `grade.py` documents.
3. Grade the lines:

   ```text
   python3 tests/story-review/grade.py RESULTS.jsonl
   ```

Spread the stories across several agents. Many fixtures share one base story,
and an agent that sees the complete version can find the gap in another
version too easily.

An expectation states the criteria that a review must raise, the criteria that
it must not raise, and the verdicts that are acceptable. A review can raise
other minor findings and questions and still pass.

The grader also checks each result against itself. The verdict must be the one
that the highest reported severity gives.

Story `31-passive-criterion` expects `report_wording` to be `first-read`, so
run the behavior test in a session that has the `first-read` skill. The agent
reports that field itself. The grader cannot see whether the agent loaded the
skill.
