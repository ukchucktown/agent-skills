---
name: first-read
description: First Read - write and audit technical prose (GitHub issues, specs, ADRs, RFCs, docs, explanations, release notes, PR descriptions, commit messages, runbooks) against a rule set adapted from ASD-STE100 Simplified Technical English. Use when writing or reviewing any prose deliverable that another person will read later, when the user asks to check, lint, or tighten writing, or when the user says "first read", "first-read", "in plain technical English", "STE", or "pte", or asks why a document is hard to read. Do not use for code, for conversational replies, or for prose in a language other than English.
---

# First Read

A rule set for technical prose. The rules come from ASD-STE100 Simplified
Technical English, Issue 9, adapted for software writing. Rule numbers such as
`(3.5)` cite the source specification.

The name is the goal: prose that a reader understands on the first read,
including a reader whose first language is not English.

## Scope test

Apply this before anything else. Two questions:

1. Is this prose that a person other than the one in this conversation will
   read later?
2. Is it English, and is it not code?

Two yes answers: apply the rules. Anything else: stop, and write normally.

- In scope: issue bodies, PR descriptions, commit messages, specs, RFCs, ADRs,
  docs, README files, release notes, runbooks, explanations written to a file.
- Guidance only, never blocking: code comments and docstrings.
- Out of scope: code, conversational replies in this session, plan text and
  todo text, and anything a person wrote that you were asked to preserve.

Do not clip your own answers to the person in front of you. This rule set is
for deliverables.

## Two modes

### Author

You are writing new prose. Load in this order:

1. `references/hard-rules.md` - 18 mechanical rules. Apply all of them.
2. `references/artifacts.md` - pick the procedural or the descriptive profile,
   then read the note for the artifact type.
3. `references/soft-targets.md` - targets and, more importantly, the anti-goals.
4. `references/word-swaps.md` - only when you reach for a word that has a
   plainer form. Read the "Words to keep" section before you swap anything in
   this domain.

**If the First Read output style is active, the hard rules are
already in your context. Do not read `hard-rules.md` again.** Read the other
three files as needed.

The output style reaches the main conversation only. A subagent runs its own
system prompt, so a subagent must read `references/hard-rules.md` itself.

### Audit

Someone asks you to check existing text. Read `references/audit.md` and follow
it. Short version: run `scripts/lint.py`, read the text for what the linter
cannot see, discard the false positives, report hard findings and soft advice
separately, and ask before you rewrite.

```bash
python3 skills/first-read/scripts/lint.py path/to/file.md
```

Add `--soft` for advisory checks. Add `--profile procedural` for a runbook or a
procedure.

## The rules in one screen

Hard, always:

no semicolons (H1) - active voice (H2) - no stacked auxiliaries (H3) - simple
tenses only (H4) - no "-ing" outside a noun (H5) - no phrasal verbs (H6) -
imperative for instructions (H7) - one instruction per sentence (H8) - condition
first, then a comma (H9) - notes inform only (H10) - warnings state the
consequence (H11) - no contractions, no dropped words (H12) - vertical lists for
complex text (H13) - articles before nouns (H14) - three words maximum in a noun
cluster (H15) - one term for one thing (H16) - no uppercase prose (H17) -
gender-neutral language (H18)

Soft, with judgment: sentence length about 20 words in a procedure and 25 in a
description - one topic in each sentence and in each paragraph - the plain word
over the elaborate one - a verb instead of a noun built from a verb - connecting
words between related sentences.

## What this rule set will not do

Read the anti-goals in `references/soft-targets.md` before you apply the soft
targets. The short version:

- It will not fragment a sentence that holds one idea to reach a word count.
- It will not replace a precise term with a vague one. "Idempotent" stays.
- It will not touch quoted text, error messages, log lines, identifiers, or
  RFC 2119 keywords.
- It does not use a closed vocabulary. The source specification has one. We
  treat vocabulary as guidance.

## Provenance

Rules adapted from ASD-STE100 Simplified Technical English, Issue 9, which is
the property of the Aerospace, Security and Defence Industries Association of
Europe (ASD). "ASD-STE100" and "Simplified Technical English" are ASD
trademarks. This rule set is not an ASD product, and ASD does not endorse it.
Read `NOTICE.md` in the repository root before you redistribute anything.
