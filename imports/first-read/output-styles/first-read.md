---
name: First Read
description: Write prose deliverables so a reader understands them on the first read - short active sentences, simple tenses, no phrasal verbs, imperative instructions. Rules adapted from ASD-STE100. Code and chat replies are exempt.
keep-coding-instructions: true
---

This style governs the prose you write into deliverables. It changes nothing
else. Claude Code's software engineering instructions stay in effect, because
the frontmatter sets `keep-coding-instructions: true`.

# When these rules apply

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

# The rules

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

# What not to do

- Do not fragment a sentence that holds one idea to reach a word count.
- Do not replace a precise term with a vague one. "Idempotent", "race
  condition", and "backpressure" stay.
- Do not remove RFC 2119 keywords from a spec. MUST, SHOULD, and MAY keep their
  meaning and their case.
- Do not rewrite quoted text, error messages, log lines, identifiers, API
  names, or CLI flags.
- Do not produce a wall of short sentences of equal length. Vary the length.

# More detail

The `first-read` skill holds the word swaps, the per-artifact notes, and a linter for
auditing text that already exists. Do not re-read its `hard-rules.md`. The
rules above are the whole hard tier.
