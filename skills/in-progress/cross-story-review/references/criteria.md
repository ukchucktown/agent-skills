# Criteria

Seven criteria for a set of stories. Each criterion gives its label, its
meaning, the signals to look for, a guard against false alarms, its default
severity, and its sources. The heading is the internal name. The label is the
name that the report shows to the authors.

Source keys:

- **QUS**: Lucassen, Dalpiaz, van der Werf, and Brinkkemper, "Improving agile
  requirements: the Quality User Story framework and tool", Requirements
  Engineering 21, 2016. Cited by criterion name. Table 1 of the paper marks
  five criteria as criteria of a set: Conflict-free, Unique, Uniform,
  Independent, and Complete.
- **Cohn**: Mike Cohn, *User Stories Applied*, 2004. Cited by chapter and
  section heading.
- **Wake**: Bill Wake, "INVEST in Good Stories, and SMART Tasks", 2003.

Two criteria, `coverage` and `traceability`, compare the set with a scope
reference. They are this skill's own, and they get `skipped` when no scope
reference was supplied. `coverage` also gets `skipped` when the stories are
one part of a larger set. The comparison of a story's rule with a
requirement, under `contradiction`, is this skill's own too.

When one piece of text matches two criteria, these rules pick the owner:

- Two stories deliver the same thing: `overlap`. Two stories state rules that
  cannot both hold: `contradiction`. The same capability with two different
  rules is a `contradiction`, because the authors must select one rule.
- Two stories deliver the same thing under two names: `overlap`. The finding
  names the two names, and `terms` gets no second finding for them.
- A story needs what another story delivers and does not say so:
  `dependency`. A story needs what no story delivers: `missing-capability`.
- The scope reference asks for something that no story delivers: `coverage`,
  also when a story needs that thing. Use `missing-capability` for a need
  that only a story shows.
- A story states a rule, and a requirement of the scope reference states a
  different rule for the same case: `contradiction`. When a second story
  states the rule of the requirement, write one finding between the two
  stories, and quote the requirement in it.
- One thing with two names: `terms`. Two names for one thing, with rules for
  it that cannot both hold: `contradiction` for the rules, and `terms` for
  the names.

## Sameness and conflict

### overlap

Label: **Overlap**

No two stories of the set deliver the same capability.

- Look for: two stories with the same role, action, and object. Two stories
  that state one capability in different words. A story whose capability is a
  part of another story of the same level.
- Result: `finding` when the texts show the same capability two times.
  `question` when a reader can take two stories as one capability or as two.
- Not a finding: a container and its own children, such as an epic and the
  stories below it, unless the child repeats the container word for word. The
  same action for two roles with different needs. Two stories that act on the
  same object with different actions. Two stories that share one acceptance
  criterion and differ in the rest.
- Severity: material. Minor when the two texts are word for word the same and
  one is plainly a copy.
- Sources: QUS "Unique".

### contradiction

Label: **Contradiction**

No story states a rule that another story of the set, or a requirement of the
scope reference, contradicts.

- Look for: two rules for the same case with different outcomes. Different
  limits, timings, or values for the same thing. A permission that one story
  gives to a role and another story withholds from that role. A state that
  one story requires and another story makes impossible. A rule of a story
  with a limit, a timing, or a value that differs from the requirement that
  the story serves.
- Result: `finding` when the two texts cannot both hold. `question` when they
  conflict only under one reading of a term that the texts leave open. A term
  that the stories plainly use for the same thing leaves nothing open.
- Not a finding: two rules for two different cases, roles, or item types. A
  general rule in one story and a stated exception in another story that
  names the general rule. A story that states more detail than its
  requirement and agrees with it.
- Severity: blocking for two stories, because the team cannot build both as
  written. Material when one of the two rules is in notes that the story
  marks as open. Material for a story against a requirement, because the team
  can build the story, and the authors must say which text is right.
- Sources: QUS "Conflict-free" for two stories. The comparison with a
  requirement is this skill's own.

## Dependence

### dependency

Label: **Dependency**

A story that needs another story of the set says so.

- Look for: a story that presumes a capability, a record, or a decision that
  another story of the set delivers, with no link and no words that name that
  story. The need can be in an acceptance criterion that names a thing of the
  other story. Two stories that each need the other. When the benefit of one story
  is the capability of another story, find out which of the two needs the
  other: the story that cannot work alone is the one that must say so.
- Result: `finding` when one story delivers what another story needs, and the
  needy story does not refer to it. Write one finding for each needy story.
  Name in it each story that it needs directly and does not name. `finding`
  for two stories that each need the other, also when both say so: write one
  finding that names both. `question` when a reader can take the text as a
  need or as a mention of the thing of the other story.
- Not a finding: a stated dependency in one direction. Stories can rarely all
  be independent, so the relation is no defect. A need that reaches the story
  through a story that it names: when C names B and B names A, C states its
  need for A. A story whose benefit, in its "so that" part, a later story
  completes, when each acceptance criterion of the story holds without the
  later one. A need for platform basics, as defined under
  `missing-capability`.
- Severity: material. Blocking for two stories that each need the other, when
  the team can build and test neither without the other. Two stories of which
  one only shows its result in a thing of the other stay material, because
  the authors can state the order. Minor when the tracker holds links for
  other stories of the set, and this need is only in the text.
- Sources: QUS "Independent". Cohn Ch. 2 "Independent". Wake "Independent".

### missing-capability

Label: **Missing capability**

What a story needs exists: the set delivers it, or the text says that it
exists already.

- Look for: a story that reads, changes, or removes a thing that no story of
  the set creates. A story that reacts to an event that no story raises. A
  story that uses a setting that no story lets a person set.
- Result: `question` to the authors ("Does X exist today, or does a story
  outside this set deliver it?"). `finding` only when the stories say that
  the thing is new and inside this set, and no story delivers it.
- Not a finding: a thing that a story says exists already, or that a named
  story outside the set delivers. Platform basics: functions outside the
  domain of the stories that any such product has, such as sign-in, the
  sending of email, or the relation between a person and their manager. A
  thing of the domain of the stories is no platform basic, so ask about it. A
  set that is one part of a larger set, for a thing that another part
  plausibly holds: ask one question for the set, not one for each story.
- Severity: material. Blocking when a story cannot start without the thing.
- Sources: QUS "Complete".

## Scope

### coverage

Label: **Coverage**

Each requirement of the scope reference has a story that delivers it.

- Look for: a requirement, a rule, or a step of the scope reference that no
  story delivers. A requirement that stories deliver only in part.
- Result: `finding` with the id and the quoted text of the requirement, when
  no story delivers it, or when the stories deliver only a part. Name the
  absent part. `question` when a reader can take a story to include it.
  `skipped` with no scope reference, and for stories that are one part of a
  larger set.
- Not a finding: a requirement that the scope reference places outside this
  set, or marks as later, optional, or undecided. A requirement about the
  project and not about the product, such as training.
- Severity: material. Blocking when other stories of the set need the absent
  part.
- Sources: this skill's own. QUS "Complete" has the idea for a set with no
  reference: no step is missing.

### traceability

Label: **Requirement behind the story**

Each story serves a requirement of the scope reference.

- Look for: a story whose capability the scope reference does not name. A
  story that goes beyond its requirement with a further capability.
- Result: `question` to the authors ("Which requirement does this story
  serve?"). A story with no requirement can be a real need that the reference
  missed, so this criterion gives no finding. `skipped` with no scope
  reference.
- Not a question: a story that makes a requirement possible, such as storage
  for a required record. A story for an error case of a required capability.
- Severity: none, because the result is a question.
- Sources: this skill's own.

## Language

### terms

Label: **Terms**

One thing has one name across the stories, and one name means one thing.

- Look for: two names for what is plainly one thing. One name that two
  stories use for two things. A general word in one story where other stories
  name the kinds.
- Result: `finding` when the texts show two names for one thing, or one name
  for two things. Name in it the stories that use the other name, and the
  first story of the set that uses the usual name. `question` when you cannot tell whether two
  names mean one thing, and for a general word that can mean one kind or all
  kinds.
- Not a finding: a term of the scope reference that the stories use as the
  reference does. Different words in the statement of the benefit. Differences
  of capital letters or of singular and plural. A full name and its short
  form, when the stories use the two side by side.
- Severity: minor. Material when a reader can build two different things from
  the two readings.
- Sources: QUS "Unambiguous", for one name with two readings and for the
  general word. The signal of two names for one thing is this skill's own.
