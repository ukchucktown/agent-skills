---
name: story-review
description: Review one user story for readiness against sourced quality criteria and return a verdict with findings. Use when the user asks to review, evaluate, check, or sign off a user story, or asks whether a story is ready for development. Not for writing new stories, and not for checks across a whole backlog.
---

# Story review

Review one user story and report a verdict, findings, and questions for the
author. Every finding rests on a criterion from `references/criteria.md`,
which records the published source behind it. The person who asked decides
whether to approve the story. The review gives them the evidence.

A story is a short statement, a conversation, and a confirmation. The review
sees only what is written. Report what the text shows and ask about the rest.
Never fill a gap with an invented rule, threshold, estimate, or priority.

## Inputs

- **Story**: the statement, the acceptance criteria, and the notes. Retrieve
  the story with whatever the session has (an issue tracker tool, a file, pasted
  text). Follow links to acceptance criteria or constraints that you can open
  before you call any detail absent.
- **Horizon**: `next` (the story is a candidate for the next iteration) or
  `later` (the story stays on the backlog for now). Default: `next`. Use
  `later` only when the user or the story says so.
- **Team checklist** (optional): a file of the team's own rules, such as a
  Definition of Ready.

Several stories in one request: review each story alone, one report per story.
Do not compare stories with each other.

## Procedure

1. **Classify the item.** Apply the `item-type` gate in
   `references/criteria.md`. For a constraint, a defect, or a technical task,
   write the short gate report below and stop. Done when the item has a type.

2. **Apply every criterion.** Read `references/criteria.md` and give each
   criterion exactly one result:
   - `finding`: the story text shows the problem. You can quote the evidence
     or name the exact absence.
   - `question`: the text suggests a problem but does not show it. Ask the
     author. Never guess toward a finding.
   - `deferred`: the criterion cannot apply yet. At horizon `later`, every
     criterion marked "next only" is deferred. A criterion entry can name one
     more case.
   - `pass`: everything else.

   Honor each criterion's "Not a finding" guard before you raise a finding.
   One defect gets one finding, under the criterion that names its cause most
   exactly. Raise a second criterion for the same text only when it needs a
   different next action. Done when all 15 criteria have a result.

3. **Apply the team checklist**, when one is supplied. Give each checklist item
   `met`, `not met`, or `cannot tell from the text`. Use `not met` when the
   item asks for something to be in the story and it is absent. Use `cannot
   tell from the text` when the item concerns a fact outside the story. Report
   these results in the "Team checklist" section, apart from the findings. A
   `not met` item counts toward the verdict as material, unless the checklist
   states its own severity.

4. **Decide the verdict.**
   - `not ready`: one or more blocking findings.
   - `needs work`: no blocking finding, and one or more material findings or
     `not met` checklist items.
   - `ready`: only minor findings, or none.

   Questions do not change the verdict. At horizon `later`, `ready` means
   "acceptable on the backlog".

5. **Report** in the format below.

## Severity

- **Blocking**: a decision is absent, and without it the team cannot estimate,
  build, or accept the story at its horizon.
- **Material**: an ambiguity or a scope problem that can plausibly cause a
  planning problem or a delivery problem.
- **Minor**: a wording improvement with little effect on shared understanding.

Each criterion states its default severity and when to raise or lower it.

## Report format

Write the report for the story's author, who does not know this skill. Use
plain words. Name each criterion by its **Label** from
`references/criteria.md`, never by its heading. Use the three group headings
below in place of the severity words. Leave the source citations out. When the
user asks for the sources, add a "Basis:" line to each finding with the
sources from the criterion entry.

```
Story review: <title or first words>
Reviewed for: the next iteration | the backlog (later work)
Result: Ready | Needs work | Not ready
<One sentence that says why.>

Must fix before work starts
1. <Label>: <what is wrong, one sentence>
   In the story: "<quoted story text>" or the named absence
   To resolve: <the smallest step that resolves it>

Should fix
2. ...

Optional improvements
3. ...

Questions for the author
- <question in plain words>

Team checklist            (only when a checklist was supplied)
- <item>: met | not met | cannot tell from the text

Checked, no problem found: <labels, comma-separated>
Not checked: <labels with the reason, or "nothing">
Could not read: <cited documents that you could not open, or "nothing">
```

Blocking findings go under "Must fix before work starts", material findings
under "Should fix", and minor findings under "Optional improvements". Leave
out a group that has no findings. Number the findings in one sequence. The
findings, the questions, the "no problem found" line, and the "not checked"
line together account for all 15 criteria. At horizon `later`, a "Ready"
result carries the words "acceptable on the backlog".

Report for an item that is not a story:

```
Item: <title or first words>
This is a <constraint | defect | technical task>, not a user story, so it was
not reviewed as one.
Better form: <one sentence from the item-type entry>
```

## Boundaries

- Report findings and questions. Leave the rewrite to the author. When a story
  is too large, name the split pattern from `references/splitting.md` that fits
  and say what kind of first slice it gives, in one sentence. The author
  chooses the slice.
- A sentence template is an aid. A story that states role, need, and benefit
  in any clear form passes. Template deviations are `minor` at most.
- Leave ticket IDs, labels, prefixes, and links alone. They are not defects.
- Cite only the sources listed in `references/criteria.md`. The procedure, the
  severities, and the verdict rule are this skill's own. Present them as such.
