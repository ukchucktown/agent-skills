# Profiles and artifact notes

## The two profiles

The source specification splits technical writing into two kinds and gives each
its own rules. Decide which kind you are writing, then apply that profile.

### Procedural

Text that tells the reader to do something: steps, runbooks, repro
instructions, migration guides, setup guides, incident procedures.

- Sentence target: about 20 words (5.1).
- Every instruction is in the imperative (H7).
- One instruction in each sentence (H8).
- Steps are numbered.
- A condition comes before the command, with a comma between them (H9).
- Notes give information only (H10).
- A limit or a result belongs in the step, not in a note.

### Descriptive

Text that explains something: issue bodies, specs, ADRs, docs, explanations,
release notes, PR descriptions, commit bodies.

- Sentence target: about 25 words (6.3).
- No imperative. You explain something. You do not instruct anyone.
- One topic in each sentence (6.1).
- One topic in each paragraph. The first sentence names it (6.4, 6.5).
- About six sentences maximum in a paragraph (6.6).
- Passive voice is permitted only when you do not know the agent (H2).

Most documents contain both. A GitHub issue is descriptive, and its "Steps to
reproduce" section is procedural. Switch profiles at the section boundary. Do
not mix the two kinds inside one list (4.3).

---

## GitHub issue

- The title stays a noun phrase. Rule 5.3 wants the imperative, and issue
  titles are an exception: they name a thing, they do not instruct anyone.
  "Consumer commits offsets before the write", not "Fix the consumer".
- The body is descriptive. State the current behavior, then the expected
  behavior, then the effect.
- "Steps to reproduce" is procedural. Number the steps. One action in each
  step.
- Paste logs, stack traces, and error strings exactly. Never rewrite them
  (anti-goal 4).
- Do not open with "I think" or "It seems like". State what you observed and
  what you did not observe.

## Pull request description

Descriptive. Three parts, in this order:

1. What the change does.
2. Why the change is necessary.
3. What a reviewer must look at, or what remains open.

Keep the first sentence able to stand alone. It becomes the summary everywhere
else.

## Commit message

- The subject line is the one place the imperative is correct in a descriptive
  artifact, because git convention requires it: "Add the retry budget", not
  "Added the retry budget".
- The body is descriptive. Say why, not what. The diff shows what.
- No contractions, no semicolons, one topic in each paragraph.

## Specification, RFC, or ADR

- Descriptive profile.
- Keep RFC 2119 keywords in uppercase: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY.
  These are normative and are not subject to the word swaps.
- Replace "shall" with "must" everywhere else.
- One requirement in each numbered statement. A requirement that contains
  "and" often holds two requirements.
- For an ADR: context, decision, consequences. The decision is one sentence in
  the simple present: "We use a single writer for the audit table."
- Define a term once, then use only that term (H16).

## Documentation and explanation

- Descriptive profile.
- Give information gradually (S2). Build each sentence on the one before it.
- Put the answer first, then the detail. A reader who stops after the first
  paragraph must still have the answer.
- A procedure inside a document switches to the procedural profile.
- Use "you" for the reader and "we" for the team. Both are correct in the
  active voice (H2).

## Release notes

- One item, one sentence, descriptive.
- Start with what changed, in the simple past or simple present.
- Name the effect on the reader, not the internal mechanism.
- Yes: The API now returns a 429 when a client exceeds its rate limit.
- No: Rate limiting has been implemented in the gateway middleware.

## Code comment

Guidance only. The hard rules apply where they cost nothing, and they never
block a change.

- Say why, not what.
- Present tense, active voice, one sentence when possible.
- Skip the article rule (H14) and the sentence-length target inside a short
  comment. "returns nil when the queue is closed" is fine.
- A docstring or a public API comment is documentation. Apply the descriptive
  profile there.

## Slack, chat, and conversational replies

Out of scope. Do not apply any of this. See the scope test in `SKILL.md`.
