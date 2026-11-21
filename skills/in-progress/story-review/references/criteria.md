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
- **Wynne**: Matt Wynne, "Introducing Example Mapping", 2015.

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
- A case that has no outcome because the story says the rule is not decided
  yet: `estimable`, not `acceptance-cases`.
- Passive or unclear wording: `sentence` when the meaning is still clear.
  `unambiguous` when two readings give different behavior.

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
- **Technical task**: work with no stated effect for a user or a purchaser.
  Suited form: a task, or a story once the author states the consequence for a
  user or a purchaser.

The name of the role does not decide the type. Ask who can do something new
when the work ships.

- A developer who uses the product is a user. An integration developer who
  calls the product's API or SDK and gets a new result is the subject of a
  story.
- A developer on the team that builds the product is not a user of it. Work
  that changes only what that team has, such as a library upgrade, is a task,
  even when it opens with "As a developer" (Lawrence).

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

Label: **Need before solution**

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
- Sources: Cohn Ch. 7 "Don't Forget the Purpose", Ch. 14 "Too Many Details".
  QUS "Minimal". Wake "Negotiable". Jeffries "Card".

### sentence

Label: **Readable wording**

The statement reads as a clear, active, complete sentence, and the acceptance
criteria are easy to read.

- Look for: fragments, shorthand, or a title with no statement. Passive
  wording that hides who acts. Wording in the statement or the acceptance
  criteria that a plain rewrite makes clearly easier to read.
- Not a finding: a clear statement that does not use the "As a, I want, so
  that" template. Ticket IDs, labels, and bracketed prefixes around the
  statement. A passive sentence whose meaning is clear, such as "A receipt is
  emailed to the buyer". Leave it, or offer one suggestion.
- Result: `finding` with a wording suggestion, only when the suggestion helps
  the author. Two suggestions at most. A wording problem alone never changes
  the verdict. When two readings of the words give different behavior, the
  defect belongs to `unambiguous`: ask which reading is right.
- Severity: minor, always.
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
- Result: `finding` when the text shows such an unknown. Otherwise `pass`.
  Never state an estimate.
- Next action: match the action to the unknown.
  - A decision: a person can settle the unknown by a choice, such as a policy
    or a business rule. Ask for the decision and name who decides, when the
    story says who.
  - An investigation: nobody can answer without work, such as a question about
    feasibility or about what an external system can do. Recommend a timeboxed
    investigation with a specific question to answer. This is the last resort
    (Lawrence, pattern "Break out a spike").
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

- Look for: no acceptance criteria in the story and no pointer to any.
  Criteria that restate the statement. Criteria that describe the
  implementation instead of an outcome.
- Not a finding: criteria in a plain list instead of given/when/then. The
  given/when/then shape is a recommendation (North). Criteria held in a linked
  document that you read. A set of criteria in which most give an observable
  result.
- Result: `unverified` when the story gives a pointer to a document in place
  of its criteria and you cannot open that document. The author supplied the
  criteria. The limit is yours, so this is not a finding and not a question
  for the author.
  `acceptance-cases` and `testable` are then `unverified` too, unless the text
  that you read settles them.
- Severity: blocking when you confirmed that there are none. Material when
  criteria exist but describe no observable result.
- Sources: Jeffries "Confirmation". Cohn Ch. 6 "Write Tests Before Coding",
  "The Customer Specifies the Tests". North.

### acceptance-cases (next only)

Label: **Acceptance cases beyond success**

The acceptance criteria reach past the success case to the cases that matter:
invalid or absent input, a refused permission, a boundary of a business rule,
a failed operation.

Check each rule that the story states against its acceptance cases. Each
value that the rule can meet needs exactly one outcome.

- Look for: only the success case, when the story plainly has a rule, a
  permission, or a failure that changes the result. A stated rule with a value
  that no case covers: with one case for "more than 24 hours" and one for
  "less than 24 hours", exactly 24 hours has no outcome. Two cases that give
  different outcomes for the same condition.
- Not a finding: a story whose behavior has no meaningful variation. Do not
  demand cases for their own sake, and do not supply the missing rules.
- Result:
  - `finding` when the criteria give only the success case.
  - `finding` when a stated rule leaves a value with no outcome, and the
    answer changes what the team must build.
  - `finding` when two cases contradict each other.
  - `question` when the text suggests a rule or a failure but does not state
    it, or when the answer to an uncovered value changes nothing that the team
    builds.
  - `deferred` when `acceptance-present` found no criteria at all.
- Severity: material.
- Next action: ask which outcome applies. Name the case, not its answer.
- Sources: Cohn Ch. 6 "How Many Tests Are Too Many?", "Types of Testing".
  North. Wynne.

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
