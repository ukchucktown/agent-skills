# cross-story-review tests

Two checks. Neither one reads or changes anything outside this repository.

## Structure and coverage

```text
./tests/cross-story-review/run.sh
```

Deterministic. It confirms that every run names a real set and real criteria,
that every key and every requirement id of an expectation exists in its set,
and that every criterion has a run that must trigger it. It also passes
deliberately wrong results to the grader and confirms that the grader rejects
them. Run it after any change to `criteria.md`, the fixtures, or `grade.py`.

## Behavior

The skill is a set of instructions for an agent, so a behavior test needs an
agent to follow them.

`fixtures/expected.json` has three runs:

| Run | Stories | Scope reference | Single-story reports |
|---|---|---|---|
| `clinic` | `sets/clinic/stories/` | `sets/clinic/reference.md` | `sets/clinic/reports/` |
| `clinic-no-reference` | `sets/clinic/stories/` | none | none |
| `clean` | `sets/clean/stories/` | none | none |

1. Give a fresh agent the skill folder and the inputs of one run. Do not show
   it `fixtures/expected.json`. Use one agent for each run, because two runs
   share one set of stories.
2. Have the agent write the full report, and then one JSON line in the shape
   that `grade.py` documents.
3. Grade the lines:

   ```text
   python3 tests/cross-story-review/grade.py RESULTS.jsonl
   ```

An expectation states the findings and the questions that a review must raise,
and the false alarms that the guards of the criteria exclude. A review can
raise other findings and questions and still pass. The run `clean` is the
exception: its stories state each dependency, so a finding there is a false
alarm.
