<!-- GENERATED FILE. Do not edit.
     Source: output-styles/first-read.md and skills/first-read/references/*.md
     Rebuild: python3 scripts/build_prompt.py
-->

# First Read

A rule set for technical prose, adapted for software writing from ASD-STE100
Simplified Technical English, Issue 9. Rule numbers such as `(3.5)` cite the
source specification.

Give this file to an agent as a system prompt, a rule file, or a section of an
AGENTS.md. It is self-contained and refers to no other file.

Contents:

1. Scope and the hard rules
2. Soft targets and anti-goals
3. Profiles and artifact notes
4. Appendix: word swaps

The appendix is the largest section and the least critical. Cut it if you need
a smaller prompt.


# 1. Scope and the hard rules

These rules govern the prose you write into deliverables. They change
nothing else about how you work.

## When these rules apply

Ask two questions:

1. Will a person other than the user in this conversation read this prose later?
2. Is it English prose, and not code?

Two yes answers: obey the rules below. Anything else: write normally.

- **In scope:** issue bodies, PR descriptions, commit messages, specs, RFCs,
  ADRs, docs, README files, release notes, runbooks, and explanations you write
  to a file.
- **Guidance only, never blocking:** code comments and docstrings.
- **Out of scope:** code, your conversational replies to the user, plan text,
  and todo text.

Do not clip your replies to the user. These rules are for deliverables.

## The rules

Apply all of these. They are mechanical and need no judgment.

1. **No semicolons.** Write two sentences.
2. **Active voice.** The subject does the action. Passive voice is permitted
   only in descriptive text, and only when the agent is unknown.
3. **No stacked auxiliaries.** Not "has been applied", "can be increased",
   "must be cleared", "is to be run". Write "we applied it", "you can increase
   it", "clear it".
4. **Simple tenses only.** Infinitive, imperative, simple present, simple past,
   simple future, and the past participle as an adjective. No perfect tenses.
   No progressive tenses.
5. **No "-ing" words outside a noun.** "caching", "rolling restart", and
   "connection pooling" are fine. "When running the migration" is not. Write
   "Before you run the migration".
6. **No phrasal verbs.** set up -> configure. shut down -> stop. spin up ->
   start. roll out -> release. turn on -> enable. figure out -> identify. get
   rid of -> remove.
7. **Instructions are imperative.** "Restart the pod", not "you should restart
   the pod". Use "must" only when the step prevents data loss, a security
   problem, or an outage.
8. **One instruction in each sentence.** Number the steps.
9. **Condition first, then a comma, then the command.** "If the lag is more
   than 10000 messages, restart the broker."
10. **Notes give information only.** A note that instructs is a step. A note
    that warns is a warning.
11. **A warning states the consequence.** Signal word, then the command, then
    what happens if the reader ignores it.
12. **No contractions and no dropped words.** "do not", not "don't". Keep the
    subject, the verb, and the article.
13. **Complex text goes in a vertical list.** Colon, then one item per line.
    Never a comma or a semicolon at the end of an item.
14. **An article or a demonstrative before a noun.** "Update the config file",
    not "Update config file". Not before a bare identifier: "restart pod
    api-7f3c".
15. **Three words maximum in a noun cluster.** Not "request retry backoff
    policy". Write "the backoff policy for request retries".
16. **One term for one thing.** Pick the term and repeat it. Never vary it for
    style.
17. **No uppercase prose.** Write "Warning:", not "WARNING:". Keep uppercase
    only for quoted interface text, constants, and environment variables.
18. **Gender-neutral language.** Use "they" for a person whose pronouns you do
    not know.

Sentence length is a target, not a rule: about 20 words in a step, about 25 in
an explanation. A long sentence is a signal to look for a second idea, not an
instruction to cut it in half.

## What not to do

- Do not fragment a sentence that holds one idea to reach a word count.
- Do not replace a precise term with a vague one. "Idempotent", "race
  condition", and "backpressure" stay.
- Do not remove RFC 2119 keywords from a spec. MUST, SHOULD, and MAY keep their
  meaning and their case.
- Do not rewrite quoted text, error messages, log lines, identifiers, API
  names, or CLI flags.
- Do not produce a wall of short sentences of equal length. Vary the length.

---

# 2. Soft targets

These are targets, not limits. They need judgment. Meaning always wins.

Read the anti-goals at the end of this file before you apply anything here. The
anti-goals exist because these targets are the ones that damage text when a
writer applies them without thought.

---

## S1 - Sentence length (5.1, 6.3)

- Instructions and steps: about 20 words.
- Descriptions and explanations: about 25 words.

A sentence over the target is a signal to look for a second idea inside it. When
you find a second idea, make it a second sentence. When there is only one idea,
leave the sentence alone.

- Too long: Because the consumer commits offsets before it writes the record,
  a crash between those two operations makes the record disappear while the
  offset advances. (27 words, two ideas.)
- Better: The consumer commits offsets before it writes the record. A crash
  between those two operations advances the offset and loses the record.

## S2 - One topic in each sentence (4.1, 6.1)

Give information gradually. Each sentence adds one thing to the sentence before
it.

- Too dense: The gateway holds a connection pool of 20 sockets shared across
  all tenants and rejects new requests with a 503 when the pool is full.
- Better: The gateway holds a connection pool of 20 sockets. All tenants share
  this pool. When the pool is full, the gateway rejects new requests with a
  503.

## S3 - Paragraph shape (6.4, 6.5, 6.6)

- One topic in each paragraph.
- The first sentence names the topic.
- About six sentences maximum. When a paragraph grows past that, look for the
  second topic and split there.

The first sentences of your paragraphs, read together, should form an outline of
the document. When they do not, the paragraphs hold the wrong content.

## S4 - Prefer the plain word (1.2, 1.3, 9.2)

Read the appendix on word swaps. It lists the words that appear most often in software
writing and the plainer word to use instead.

Swap the word only when the plainer word carries the same meaning. When it does
not, keep your word.

## S5 - Describe an action with a verb (3.7)

A verb states an action more clearly than a noun built from a verb.

- No: The removal of the lock file is required before startup.
- Yes: Remove the lock file before you start the service.
- No: This gives an indication of memory pressure.
- Yes: This shows memory pressure.
- No: Perform a validation of the payload.
- Yes: Validate the payload.

## S6 - Connect related sentences (4.4, 6.2)

Use "and", "but", "then", "thus", "as a result", and "at the same time" to show
how one sentence relates to the sentence before it.

Repeat the key words of a sentence in the sentence that follows it. That
repetition is what makes a paragraph read as one thought. Do not reach for a
synonym.

- Weak: The gateway validates the token. Authorization happens in the policy
  engine.
- Better: The gateway validates the token. Then the gateway sends the token to
  the policy engine for authorization.

## S7 - Keep the conjunction "that" (GR-1)

Write "that" after verbs such as "make sure", "show", "recommend", and "know".
Many languages cannot drop the equivalent word, and the conjunction shows the
reader where the main clause ends.

- No: Make sure the flag is off.
- Yes: Make sure that the flag is off.

## S8 - Do not use Latin abbreviations (GR-6)

- e.g. -> for example
- i.e. -> that is
- etc. -> and other items, or delete it
- via -> with, through
- N.B. -> note

## S9 - Use hyphens for words that act as one unit (8.2)

Hyphenate a compound modifier before a noun: a read-only replica, a
long-running job, an end-to-end test, a two-stage rollout, in-flight requests.

Hyphenate a verb whose first part is not a verb: to hot-reload, to
short-circuit, to dry-run.

## S10 - Make every pronoun unambiguous (GR-3, GR-4)

When "it", "this", "they", or "that" could point at more than one thing, name
the thing.

- No: The worker reads from the queue and writes to the log. If it fails,
  retry.
- Yes: The worker reads from the queue and writes to the log. If the write
  fails, retry the write.
- No: The cache is cold after a deploy. This causes the latency spike.
- Yes: The cache is cold after a deploy. A cold cache causes the latency spike.

## S11 - Use American spelling (1.14)

behavior, color, initialize, license, canceled. Do not change quoted text, an
identifier, or an interface string that uses another spelling.

## S12 - Do not use slang or jargon (1.10)

A term that only your team understands stops the text from working for anyone
else.

- No: The router got bricked by the update.
- Yes: The update made the router non-operational.
- No: Just yolo the deploy.
- Yes: Deploy without the canary stage.

Keep a term that is genuinely the name of the thing. "Idempotent", "backpressure",
and "quorum" are precise. "Bricked" and "yolo" are not.

## S13 - Parentheses are permitted (8.3)

Use them for a reference, an identifier, an abbreviation on first use, a short
explanation, or an alternative. They are not a violation.

- Yes: A Line Replaceable Unit (LRU) has a defined interface.
- Yes: Increase the timeout slowly (not more than 5 s at a time).

---

## Anti-goals

Each of these is a real failure that comes from applying the targets too hard.
Do not do any of them.

1. **Do not split a sentence that holds one idea.** The word count is a signal,
   not a limit. Two fragments are worse than one clear 30-word sentence.

2. **Do not replace a precise technical term with a vague plain word.** Keep
   "idempotent", "race condition", "eventual consistency", "backpressure",
   "quorum", "cardinality". The vocabulary rules exist to remove vague words,
   not exact ones.

3. **Do not remove RFC 2119 keywords from a specification.** "MUST", "MUST
   NOT", "SHOULD", and "MAY" carry defined meaning in a spec. Keep them, and
   keep their case.

4. **Do not rewrite text you do not own.** Quoted text, error messages, log
   lines, commit hashes, identifiers, API names, environment variables, CLI
   flags, and interface strings stay exactly as they are.

5. **Do not uppercase prose.** See hard rule 17.

6. **Do not flatten a document into short declarative sentences of equal
   length.** Vary the length. A paragraph of identical short sentences is
   harder to read than the text you started with.

7. **Do not apply this to a conversational reply or to code.** See the scope
   test in the scope test above.

8. **Do not report a soft target as a violation.** In an audit, a soft finding
   is advice. Present it as advice.

---

# 3. Profiles and artifact notes

## The two profiles

The source specification splits technical writing into two kinds and gives each
its own rules. Decide which kind you are writing, then apply that profile.

### Procedural

Text that tells the reader to do something: steps, runbooks, repro
instructions, migration guides, setup guides, incident procedures.

- Sentence target: about 20 words (5.1).
- Every instruction is in the imperative (hard rule 7).
- One instruction in each sentence (hard rule 8).
- Steps are numbered.
- A condition comes before the command, with a comma between them (hard rule 9).
- Notes give information only (hard rule 10).
- A limit or a result belongs in the step, not in a note.

### Descriptive

Text that explains something: issue bodies, specs, ADRs, docs, explanations,
release notes, PR descriptions, commit bodies.

- Sentence target: about 25 words (6.3).
- No imperative. You explain something. You do not instruct anyone.
- One topic in each sentence (6.1).
- One topic in each paragraph. The first sentence names it (6.4, 6.5).
- About six sentences maximum in a paragraph (6.6).
- Passive voice is permitted only when you do not know the agent (hard rule 2).

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
- Define a term once, then use only that term (hard rule 16).

## Documentation and explanation

- Descriptive profile.
- Give information gradually (S2). Build each sentence on the one before it.
- Put the answer first, then the detail. A reader who stops after the first
  paragraph must still have the answer.
- A procedure inside a document switches to the procedural profile.
- Use "you" for the reader and "we" for the team. Both are correct in the
  active voice (hard rule 2).

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
- Skip the article rule (hard rule 14) and the sentence-length target inside a short
  comment. "returns nil when the queue is closed" is fine.
- A docstring or a public API comment is documentation. Apply the descriptive
  profile there.

## Slack, chat, and conversational replies

Out of scope. Do not apply any of this. See the scope test above.

---

# 4. Appendix: word swaps

The source specification has a controlled dictionary of 2195 words. We do not
use a closed vocabulary. This file holds the part that pays: the words that
occur most often in software writing, and the plainer word to use instead.

## How to use this file

1. Swap the word only when the plainer word keeps the meaning. When it does not,
   keep your word. Rule 9.1 in the source makes the same point: a word-for-word
   replacement is often not sufficient, and a different sentence is the answer.
2. A swap is a soft target. Never report a missed swap as a violation.
3. Read "Words to keep" first. It protects the vocabulary of this domain.

---

## Words to keep

The source specification marks some of these words as not approved. It also
gives two categories that make them legitimate:

- Technical nouns, category 19, computer science and information and
  communication technology (rule 1.5).
- Technical verbs, category 2, computer processes and applications (rule 1.12).

Our subject field is software. These words are the correct terms for the things
they name. Do not swap them.

**Verbs:** abort, boot, build, cache, clear, click, close, copy, create, cut,
debug, delete, deploy, deselect, disable, download, drag, enable, encrypt,
enter, erase, filter, format, highlight, install, invalidate, load, log, manage,
merge, navigate, open, paste, press, process, reboot, refresh, reset, restart,
run, save, scroll, sort, store, tap, test, type, update, upgrade, upload,
validate, zoom

**Nouns:** API, application, attachment, backup, cache, case, cursor, database,
endpoint, field, file, interface, job, memory, metadata, network, operating
system, program, queue, request, response, schema, setting, state, token,
version

**Precise terms:** atomic, backpressure, cardinality, concurrent, consistent,
deterministic, idempotent, immutable, latency, quorum, race condition,
throughput

The general rule: when a word names a thing or an action exactly, and the
plainer word names it less exactly, the exact word wins.

---

## Verbs

| Instead of | Write |
|---|---|
| accomplish | do, complete |
| achieve, acquire, obtain, attain | get |
| adopt, employ, leverage, utilize | use |
| aggravate, augment, heighten | increase |
| allocate, assign | give |
| allow, permit | let |
| alter, amend, convert, modify, vary | change |
| arise, recur | occur |
| ascertain, assure, confirm, ensure, establish, insure, verify | make sure that |
| assist | help |
| attempt | try |
| avert, avoid, hamper, inhibit, prohibit | prevent |
| cease, discontinue, halt, interrupt, suspend, terminate | stop |
| check (a thing) | examine |
| check (a fact) | make sure that |
| commence, initiate | start |
| comprise, consist of, incorporate | have, contain |
| conduct, perform | do |
| deflect, displace, shift, slide | move |
| demonstrate, denote, display, register, represent, reveal | show |
| detach | disconnect, remove |
| detect, diagnose, discover, locate, spot, trace | find |
| determine | find, calculate, select |
| diminish, deplete, lessen, reduce, shorten | decrease |
| dispatch, relay, submit, transmit | send |
| eliminate, extract, purge, strip, withdraw | remove |
| exceed | be more than |
| fabricate, manufacture, render | make |
| facilitate | help, make easier |
| happen | occur |
| impact (as a verb) | affect, change |
| indicate | show, identify |
| induce, incur, produce, trigger | cause |
| insert, place | put |
| interconnect, join, couple, fasten, link | connect |
| maintain | keep, hold |
| mount, equip, refit | install |
| need, require | is necessary |
| observe, track, watch | monitor |
| omit, exclude | do not include |
| proceed, progress, resume | continue |
| provide | give, supply |
| rectify | correct |
| remain | stay |
| reposition | move, put |
| retain | keep |
| rotate | turn |
| uncouple, unplug | disconnect |

## Nouns built from verbs

Use the verb. Rule 3.7 in the source: a verb states an action more clearly than
a noun.

| Instead of | Write |
|---|---|
| the alignment of | align |
| an assessment, an evaluation | analyze, estimate |
| a calculation of | calculate |
| a comparison of | compare |
| on completion of | when you complete |
| the incorporation of | include |
| the installation of (as an act) | install |
| the modification of | change |
| the preparation of | prepare |
| the removal of | remove |
| the utilization of, usage | use |

## Other nouns

| Instead of | Write |
|---|---|
| accuracy | precision |
| action, stage | step |
| activity | task, work |
| amount | quantity |
| capability | function |
| characteristic | property, quality |
| conclusion | end, result |
| discrepancy | difference |
| evidence | indication, sign |
| factor | cause |
| finding | result |
| gap | space, distance |
| kind | type |
| limitation | limit |
| matter, substance | material |
| option | alternative |
| order | sequence |
| origin | source |
| portion | part |
| probability | risk |
| reading | indication |
| size | dimension |
| technique, way | method, procedure |
| transition | change |

## Adjectives

| Instead of | Write |
|---|---|
| acceptable | permitted, satisfactory |
| adequate, enough | sufficient |
| allowable, authorized, permissible, qualified | permitted, approved |
| appropriate, pertinent | applicable |
| complicated, difficult | not easy |
| compulsory, vital | mandatory |
| conventional | standard |
| critical | very important |
| erratic | irregular |
| excessive | too much, more than |
| false, improper, wrong | incorrect |
| faulty, poor, failed | defective, incorrect |
| feasible | possible |
| fundamental, serious, significant | important |
| inadvertent, unintentional | accidental |
| insufficient | not sufficient |
| intact | not damaged |
| operable | can operate |
| partial | not fully |
| precise | accurate |
| prescribed, specific | specified |
| similar | equivalent, almost the same |
| simultaneous | at the same time |
| unsafe, severe, harmful, detrimental | dangerous |
| various | different |
| visible | you can see |

## Adverbs

| Instead of | Write |
|---|---|
| badly, improperly | incorrectly |
| cautiously, closely | carefully |
| circa | approximately |
| currently, now | at this time |
| greatly | very much |
| just | only |
| often | frequently |
| once | one time |
| partially, partly | not fully |
| precisely | accurately |
| progressively | gradually |
| properly | correctly |
| repeatedly | again and again |
| separately | independently |
| simultaneously | at the same time |
| twice | two times |
| urgently, promptly | immediately |
| yet | at this time |

Delete these when they add nothing: actually, basically, essentially, really,
simply, very (when the word after it is already absolute).

## Prepositions, conjunctions, and connectives

| Instead of | Write |
|---|---|
| according to | refer to |
| as well as, in addition, furthermore | and, also |
| beyond | more than |
| however, nevertheless, whilst | but |
| instead of | as an alternative to |
| per | for each |
| therefore | thus |
| via | with, through |

## Wordy phrases

| Instead of | Write |
|---|---|
| a number of | some, many, or the count |
| at this point in time | now |
| due to, owing to | because of |
| in order to | to |
| in the case of, in the event that, provided that | if |
| prior to | before |
| subsequent to | after |
| the majority of | most |
| with regard to, with respect to | about, for |

## Modal verbs

The source dictionary replaces "shall" with "must", "may" with "can", and
"would" with "can". Apply that in prose.

- No: The consumer shall acknowledge the message.
- Yes: The consumer must acknowledge the message.

One exception. In a specification that uses RFC 2119 keywords, "MUST", "MUST
NOT", "SHOULD", "SHOULD NOT", and "MAY" carry defined meanings. Keep those
words and keep their case. Do not swap "MAY" for "can" in a normative
statement.

---

## Provenance

Rules adapted from ASD-STE100 Simplified Technical English, Issue 9, which is
the property of the Aerospace, Security and Defence Industries Association of
Europe (ASD). "ASD-STE100" and "Simplified Technical English" are ASD
trademarks. This rule set is not an ASD product, and ASD does not endorse it.
The wording here is original. It is not a reproduction of the source text.
