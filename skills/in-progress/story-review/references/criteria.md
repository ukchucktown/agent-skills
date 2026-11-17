# Criteria

One gate and 15 criteria. Each criterion gives its label, its meaning, the
signals to look for, a guard against false alarms, its default severity, and
its sources. The heading is the internal name. The label is the name that the
report shows to the author.

Source keys:

- **Cohn**: Mike Cohn, *User Stories Applied*, 2004. Cited by chapter and
  section heading.
- **Wake**: Bill Wake, "INVEST in Good Stories, and SMART Tasks", 2003.
- **Jeffries**: Ron Jeffries, "Essential XP: Card, Conversation,
  Confirmation", 2001.
- **North**: Dan North, "What's in a Story?", 2007.
- **Lawrence**: Richard Lawrence and Peter Green, "The Humanizing Work Guide to
  Splitting User Stories".
- **QUS**: Lucassen, Dalpiaz, van der Werf, and Brinkkemper, "Improving agile
  requirements: the Quality User Story framework and tool", Requirements
  Engineering 21, 2016. Cited by criterion name.

Criteria marked **next only** get `deferred` at horizon `later`. A story for
later work can be broad, can bundle capabilities, and can lack acceptance
criteria (Cohn Ch. 7 "Size the Story to the Horizon").

When one piece of text matches two criteria, these rules pick the owner:

- Several capabilities in one story: `atomic`. Add `size` only when the story
  is plainly more than one iteration of work.
- Solution detail in the statement or the acceptance criteria:
  `need-not-solution`. Solution detail in the notes: `detail`.
- Subjective words in the acceptance criteria: `testable`, not
  `acceptance-present` and not `unambiguous`.
- An open-ended verb such as "manage": `closed`. Leave `size` as a question
  until the author names the acts.

## Gate

### item-type

Decide what the item is before you judge it as a story.

- **Story**: a change in what some person can do or get.
- **Constraint**: a quality that the system must keep across many stories, such
  as a response time, a security rule, or a supported platform. Suited form: a
  constraint recorded once, with a measurable target, and checked against every
  story it touches.
- **Defect**: existing behavior that is wrong. Suited form: a defect report
  with the steps, the expected result, and the actual result.
- **Technical task**: work with no stated effect for a user or a purchaser. A
  task that opens with "As a developer" is still a task (Lawrence). Suited
  form: a task, or a story once the author states the consequence for a user
  or a purchaser.

Only a story continues to the criteria. Technical work that states its
consequence for a user or a purchaser is a story. A quality target for one
capability, with a role and a need, is a story. Judge it with `testable`.

Sources: Cohn Ch. 7 "Some Things Aren't Stories", "Put Constraints on Cards".
Lawrence.

## Statement

### role

Label: **Role**

The story names one specific role that gets the result.

- Look for: no role at all. "The user" or "users" when the product has distinct
  kinds of user. Two roles joined in one story. A system or a team as the role.
- Not a finding: a role given in the title, a label, or a persona name instead
  of an "As a" clause. A role name that contains "&" or "/", such as "R&D
  Manager".
- Severity: material. Minor when the role is generic and the context makes the
  real role obvious.
- Sources: Cohn Ch. 7 "Include User Roles in the Stories", "Write for One
  User". QUS "Well-formed". North.

### value

Label: **Benefit**

The story shows who benefits and why the work is worth doing.

- Look for: no stated benefit and none evident from the context. A benefit that
  restates the feature ("so that I can use the feature"). A benefit only for
  the developers.
- Not a finding: a benefit for a purchaser or the organization instead of an
  end user, such as audit evidence or lower running cost. A benefit stated in
  the notes instead of a "so that" clause.
- Severity: material.
- Sources: Cohn Ch. 2 "Valuable to Purchasers or Users". Wake "Valuable". QUS
  "Conceptually sound". North.

### atomic (next only)

Label: **Single request**

The story asks for one capability.

- Look for: two capabilities joined by "and", "or", "as well as", or a list.
  Acceptance criteria that fall into unrelated groups.
- Not a finding: "and" inside a role name or inside one capability ("search
  and filter results" can be one act). Several acceptance cases for the same
  capability. Two qualities of one capability ("fast and easy").
- Severity: material.
- Sources: QUS "Atomic".

### closed (next only)

Label: **Finish point**

The story has a finish point: the person completes something meaningful.

- Look for: open-ended verbs with no end state, such as "manage", "handle",
  "administer", "work with", "maintain".
- Not a finding: an open-ended verb in the title when the statement or the
  acceptance criteria name the finished act.
- Severity: material.
- Sources: Cohn Ch. 7 "Write Closed Stories". Lawrence (pattern "Operations").

### need-not-solution

Label: **Need, not solution**

The story states the need and leaves the solution open.

- Look for: named widgets, screen positions, colors, tables, endpoints, or
  libraries in the statement or the acceptance criteria. A statement that
  describes how the system works inside.
- Not a finding: a solution detail that the story marks as a settled decision
  or a constraint, with its reason or a link. Domain terms that sound technical
  but are the user's own words.
- Severity: material. Minor for one passing hint that does not limit the
  design.
- Sources: Cohn Ch. 2 "Negotiable", Ch. 7 "Keep the UI Out as Long as
  Possible", Ch. 14 "Including User Interface Detail Too Soon". Wake
  "Negotiable". QUS "Problem-oriented".

### vertical-slice

Label: **Usable on its own**

The story delivers a result that a person can use. It cuts through every layer
that the result needs.

- Look for: a story for one layer only ("build the screen", "create the
  table", "add the endpoint"). A story whose result becomes usable only after a
  different story finishes.
- Not a finding: a thin first version that works end to end with limited data
  or a simple interface.
- Severity: material.
- Sources: Cohn Ch. 7 "Slice the Cake". Wake "Valuable". Lawrence. North.

### unambiguous

Label: **Clear wording**

The words in the story have one reasonable meaning.

- Look for: undefined collective nouns ("content", "activity", "data",
  "details"). Relative words with no reference ("recent", "large", "soon").
  A pronoun that can point at two things. A term used in two senses.
- Not a finding: a domain term that the team's glossary, the notes, or a linked
  document defines. Subjective quality words in the acceptance criteria (use
  `testable` for those).
- Severity: material. Blocking when the scope of the story depends on the
  ambiguous word.
- Sources: QUS "Unambiguous".

### detail

Label: **Level of detail**

The story carries enough detail to restart the conversation, and no more.

- Look for: step-by-step implementation notes, schema or class names, pasted
  specifications, or design decisions that the team does not need to make yet.
- Not a finding: acceptance criteria, however many. Business rules and policy
  facts. Links to supporting documents. Settled constraints.
- Severity: minor. Material when the extra detail contradicts the statement or
  the acceptance criteria.
- Sources: Cohn Ch. 14 "Too Many Details". QUS "Minimal". Wake "Negotiable".
  Jeffries "Card".

### sentence

Label: **Readable statement**

The statement reads as a clear, active, complete sentence.

- Look for: fragments, shorthand, or a title with no statement. Passive
  wording that hides who acts.
- Not a finding: a clear statement that does not use the "As a, I want, so
  that" template. Ticket IDs, labels, and bracketed prefixes around the
  statement.
- Severity: minor.
- Sources: Cohn Ch. 7 "Write in Active Voice". QUS "Full sentence".

## Size

### size (next only)

Label: **Size**

The story is small enough to finish within one iteration.

- Look for: several workflows or several operations in one story. More than
  about six distinct acceptance scenarios (North). Words such as "all",
  "every", "end to end", or "complete" around a broad noun.
- Not a finding: a story with many acceptance cases that all exercise one
  capability.
- Severity: material. Blocking when the story is plainly several iterations of
  work.
- Next action: name the pattern from `splitting.md` that fits. When `atomic`
  fires on the same text, point to that finding's action instead.
- Sources: Cohn Ch. 2 "Small", Ch. 7 "Size the Story to the Horizon". Wake
  "Small". North. Lawrence.

### estimable (next only)

Label: **Open unknowns**

Nothing visible in the story prevents the team from estimating it. Only the
team can estimate. The review looks for unknowns that the text itself shows.

- Look for: a stated open question about feasibility, an external system, or a
  rule that the scope depends on. "TBD" or "to be confirmed" on a point that
  changes the work.
- Not a finding: an open question about a detail that does not change the
  scope. The absence of an estimate.
- Result: `finding` when the text shows such an unknown. Recommend a timeboxed
  investigation with a specific question to answer. Otherwise `pass`. Never
  state an estimate.
- Severity: material. Blocking when the whole story depends on the unknown.
- Sources: Cohn Ch. 2 "Estimatable". Wake "Estimable". QUS "Estimatable".
  North.

## Acceptance

### testable (next only)

Label: **Testable outcome**

A test can show whether the story succeeded.

- Look for: subjective or absolute targets with no measure ("fast", "easy",
  "intuitive", "never fails", "user friendly"). An outcome that nobody can
  observe.
- Not a finding: a quality target with a number and a condition. A usability
  outcome with a named evaluation method.
- Severity: material. Blocking when no part of the story gives an observable
  outcome.
- Sources: Cohn Ch. 2 "Testable". Wake "Testable".

### acceptance-present (next only)

Label: **Acceptance criteria present**

The story has acceptance criteria, and a person can observe each result.

- Look for: no acceptance criteria in the story and none at any link you can
  open. Criteria that restate the statement. Criteria that describe the
  implementation instead of an outcome.
- Not a finding: criteria in a plain list instead of given/when/then. The
  given/when/then shape is a recommendation (North). Criteria held in a linked
  document that you read. A set of criteria in which most give an observable
  result.
- Severity: blocking when there are none. Material when criteria exist but
  describe no observable result.
- Sources: Jeffries "Confirmation". Cohn Ch. 6 "Write Tests Before Coding",
  "The Customer Specifies the Tests". North.

### acceptance-cases (next only)

Label: **Acceptance cases beyond success**

The acceptance criteria reach past the success case to the cases that matter:
invalid or absent input, a refused permission, a boundary of a business rule,
a failed operation.

- Look for: only the success case, when the story plainly has a rule, a
  permission, or a failure that changes the result.
- Not a finding: a story whose behavior has no meaningful variation. Do not
  demand cases for their own sake, and do not supply the missing rules.
- Result: `finding` when the criteria give only the success case. `question`
  when failure cases exist and one case stays open. `deferred` when
  `acceptance-present` found no criteria at all.
- Severity: material.
- Next action: ask which case applies. Name the case, not its answer.
- Sources: Cohn Ch. 6 "How Many Tests Are Too Many?", "Types of Testing".
  North.

## Dependencies

### prerequisites

Label: **Prerequisites**

The story states what must exist before it can work.

- Look for: a story that presumes a capability, a data source, or a decision
  whose existence the text does not establish.
- Result: `question` to the author ("Does X exist today, or does a different
  story deliver it?"). `pass` when the story names its prerequisites. Full
  independence is rarely possible, so a dependency is not a defect. An unstated
  dependency is the concern.
- Not a question: platform basics that any such product has, such as sign-in,
  an existing list, or a profile page. Ask only about a capability that this
  story's result depends on directly. Two questions at most.
- Sources: Cohn Ch. 2 "Independent". Wake "Independent". QUS "Independent".
