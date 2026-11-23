---
name: cross-story-review
description: Review a set of user stories together for problems that lie between stories, such as overlap, contradiction, missing pieces, hidden dependencies, and inconsistent terms, and return findings with evidence. Use when the user asks to review a backlog, an epic, or several stories together, or asks whether stories overlap, conflict, or depend on each other. Not for the quality of one story, and not for priority, value order, or estimates.
---

# Cross-story review

Review what lies between the stories of a set, and report findings and
questions for the authors. Every finding rests on a criterion from
`references/criteria.md`, which records the source behind it.

This skill judges relations between stories. It gives no verdict, and it
judges no story alone: role, value, size, and acceptance criteria belong to a
review of one story. Report what the texts show and ask about the rest. Never
fill a gap with an invented rule, requirement, or dependency.

## Inputs

- **Stories**: two or more stories that the session already holds, each with
  its statement, its acceptance criteria, its notes, and its stated links to
  other stories. With one story, stop and say that this review needs two or
  more. Give each story a key. Use the key of the tracker when it has one,
  and a number in the order of the input, such as `#1`, when it has none. A
  stated link is a link of the tracker, or words of a story that name another
  story as something that it needs or uses.
- **Name of the set**: the name that the requester gave, or the title of the
  item above the stories. With neither, use `Stories <first key> to <last
  key>`.
- **Scope reference** (optional): a statement of what the set must deliver,
  such as a requirements document or the description of the parent item, with
  a name and a version or a date. Use the ids of the reference. When it has
  none, number its statements `S1`, `S2`, and so on, in their order. Without
  a scope reference, the criteria `coverage` and `traceability` get the
  result `skipped`, and no story is compared with a requirement.
- **Part of a larger set** (optional): the statement that the stories are one
  part of the set that the scope reference covers. Then `coverage` gets
  `skipped`, because another part can deliver a requirement.
- **Per-story reports** (optional): the report of a single-story review for
  each story. With them, step 4 adds notes to their questions and findings.
  Without them, leave step 4 out.

## Procedure

1. **Summarize each story.** Write one summary for each story in the form
   below. A summary is a reading aid that makes two stories comparable. It is
   never evidence. Done when every story has a summary.

2. **Select the stories to compare.** Compare two stories when their
   summaries share an object, a term, a role with the same need, or the
   subject of a rule, or when one presumes what the other delivers. In a set
   of ten stories or fewer, compare every pair. Done when every pair of a
   small set was compared, or when every story of a larger set was compared
   with each story that it shares one of these with.

3. **Apply every criterion.** Read `references/criteria.md` and apply each
   criterion to the set. A criterion gives findings, questions, or both:
   - `finding`: the text of the stories shows the problem. Each finding names
     its stories and quotes the text of each one. Go back to the story text
     for the quote. A summary does not prove a finding.
   - `question`: the texts suggest a problem and do not show it. Ask the
     authors. Never guess toward a finding.

   A criterion with no finding and no question gets one of two results:
   - `skipped`: the criterion needs an input that was not supplied.
   - `pass`: the criterion was applied, and it found no problem.

   Honor each criterion's "Not a finding" guard before you raise a finding.
   One problem gets one finding, under the criterion that names its cause most
   exactly. Done when all 7 criteria have findings, questions, a `skipped`, or
   a `pass`.

4. **Add notes to the per-story reports**, when they were supplied. For each
   question and each finding of a per-story report, look in the other stories
   and in the scope reference for the answer.
   - Another story holds the answer, and the story does not refer to it: write
     a note that names the other story and quotes the answer. The missing
     reference is a `dependency` finding when the story needs the other one.
   - Another story holds the answer, and the story refers to it: write a note
     that says so.
   - The scope reference holds the answer: write a note that names the id of
     the requirement and quotes it.
   - Nothing holds the answer: write nothing. The question stays as it is.

   Write one note for each item, and name in it the story that states the
   answer most directly. Name a requirement only when no story holds the
   answer. A note never changes a per-story report, its
   findings, or its verdict. Done when each question and each finding of each
   report was checked.

5. **Report** in the format below. Write the words of the report with the
   `first-read` skill in Author mode, when the session has that skill. Keep
   the report headings as they are, and copy quoted text exactly. When the
   session does not have `first-read`, use the wording rules under "Report
   format". Done when the report accounts for all 7 criteria, and each
   finding has a quote for each of its stories.

## Summary of one story

```
Story: <key> <title>
Role: <who the story is for>
Delivers: <each capability, one line each, in the words of the story>
Presumes: <each capability, data source, or decision that the story needs and
  does not deliver. Add "stated: <key>" when the story names the story that
  delivers it, or "unstated">
Acts on: <each thing that the story reads, creates, changes, or removes, with
  the verb>
Rules: <each rule, limit, timing, or permission that the story states>
Terms: <the domain terms of the story, as written>
Traces to: <ids of the scope reference> | none found | no scope reference
```

For a set of more than ten stories, write the summaries one story at a time.
Write each one from the text of that story alone, and use the scope reference
only for the line `Traces to`. Then run steps 2 to 5 on the summaries, and
open the story texts for each comparison that a summary suggests.

## Severity

- **Blocking**: the stories cannot all be built as written, or a story cannot
  start, because the set contradicts itself or delivers nowhere what a story
  needs.
- **Material**: a relation between stories that can plausibly cause a planning
  problem or a delivery problem.
- **Minor**: an improvement of wording or of references with little effect on
  shared understanding.

Each criterion states its default severity and when to raise or lower it.

## Report format

Write the report for the authors of the stories, who do not know this skill.
Name each criterion by its **Label** from `references/criteria.md`, never by
its heading. Use the three group headings below in place of the severity
words. Leave the source citations out. When the user asks for the sources,
add a "Basis:" line to each finding with the sources from the criterion
entry.

```
Cross-story review: <name of the set>, <number> stories
Scope reference: <name and version> | none
<One sentence that says what the review found.>

Must fix before work starts
1. <Label>: <what is wrong>
   Stories: <key>, <key> | none
   In <key>: "<quoted story text>"
   In <key>: "<quoted story text>" or the named absence
   In <requirement id>: "<quoted requirement>"
   To resolve: <the smallest step that resolves it>

Should fix
2. ...

Optional improvements
3. ...

Questions for the authors
- <Label>, <keys>: <question in plain words>

Order of work
- <key> before <key>: <the reason, in a few words>
- <key> and <key>: each needs the other

Notes on the single-story reviews
- <key>, <the question, or the label of the finding, in a few words>: <key or
  requirement id> answers it: "<quoted text>". <The story refers to that
  story. | The story does not refer to that story.>

Checked, no problem found: <labels, comma-separated, or "nothing">
Not checked: <Label> (<reason>), <Label> (<reason>) | nothing
```

Blocking findings go under "Must fix before work starts", material findings
under "Should fix", and minor findings under "Optional improvements". Number
the findings in one sequence. Leave out each of these parts when it has no
entry: a group of findings, "Questions for the authors", "Order of work", and
"Notes on the single-story reviews". The summaries of step 1 are no part of
the report.

A finding has one "In <key>:" line for each story that it names. A finding
against the scope reference has the line "In <requirement id>:" with the
quoted requirement. A finding between two stories can have that line too,
when a requirement shows which of the two texts is right. When no story takes part in such a finding, its
"Stories:" line says "none".

The findings, the questions, the "no problem found" line, and the "not
checked" line together account for all 7 criteria. A `skipped` criterion goes
on the "Not checked" line with its reason: "no scope reference", or "the
stories are one part of a larger set".

"Order of work" lists each pair where one story must exist before the other
works. It takes the pairs from the `dependency` findings and from the stated
links that say "needs" or "depends on". It lists a direct pair only: with A
before B and B before C, it has no line for A before C. Two stories that each need the other get one line with "and". The
part states an order of dependence. It states no priority.

Wording rules for a session without `first-read`:

- Use the active voice, and name who acts.
- Put one fact or one instruction in each sentence.
- Use one term for one thing, and use the terms of the stories.
- Write every word. Do not drop articles, and do not use shorthand.
- Use plain words. Leave out idioms and hedges.

## Boundaries

- Report findings and questions. Leave the rewrite, the merge, and the split
  to the authors.
- Judge no story alone. A problem that one story shows without any other
  story and without the scope reference belongs to a single-story review.
- State no priority, no value order, and no estimate. "Order of work" is the
  only statement about sequence.
- A dependency between stories is no defect. Full independence is rarely
  possible. The unstated dependency is the concern.
- Cite only the sources listed in `references/criteria.md`. The procedure, the
  summary, the severities, and each comparison with a scope reference are
  this skill's own. Present them as such.
