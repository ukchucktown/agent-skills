# Soft targets

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

Read `word-swaps.md`. It lists the words that appear most often in software
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

5. **Do not uppercase prose.** See H17.

6. **Do not flatten a document into short declarative sentences of equal
   length.** Vary the length. A paragraph of identical short sentences is
   harder to read than the text you started with.

7. **Do not apply this to a conversational reply or to code.** See the scope
   test in `SKILL.md`.

8. **Do not report a soft target as a violation.** In an audit, a soft finding
   is advice. Present it as advice.
