---
name: first-read
description: First Read - write and audit technical prose (GitHub issues, specs, ADRs, RFCs, docs, explanations, release notes, PR descriptions, commit messages, runbooks) against a rule set adapted from ASD-STE100 Simplified Technical English. Use when writing or reviewing any prose deliverable that another person will read later, when the user asks to check, lint, or tighten writing, or when the user says "first read", "first-read", "in plain technical English", "STE", or "pte", asks why a document is hard to read, or asks to remove AI-sounding wording. Do not use for code, for conversational replies, or for prose in a language other than English.
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
- In scope with the casual profile: a post, an announcement, or an email that
  the person asks you to draft or to rewrite.
- Guidance only, never blocking: code comments and docstrings.
- Out of scope: code, conversational replies in this session, plan text and
  todo text, and anything a person wrote that you were asked to preserve.

Do not clip your own answers to the person in front of you. This rule set is
for deliverables.

## Two modes

### Author

You write new prose, or you rewrite prose with the agreement of its owner.
Load in this order:

1. `references/hard-rules.md` - 18 mechanical rules. Apply all of them.
2. `references/artifacts.md` - pick the procedural, the descriptive, or the
   casual profile, then read the note for the artifact type.
3. `references/soft-targets.md` - targets and, more importantly, the anti-goals.
4. `references/ai-tells.md` - 13 habits that a reader recognizes as machine
   writing.
5. `references/fidelity.md` - only when you rewrite text or write from source
   material such as a diff, a log, or a thread.
6. `references/word-swaps.md` - only when you reach for a word that has a
   plainer form. Read the "Words to keep" section before you swap anything in
   this domain.

Then write in this order:

1. Draft each paragraph for meaning. Give each claim its reason, its
   condition, or its result in the same sentence.
2. Apply the hard rules. When a rule removes a construction, rebuild the
   sentence. Join a claim to its reason, its condition, or its result with a
   connecting word ("because", "so", "which", "when"). Put a period between
   two separate claims.
3. Read each paragraph from its first sentence to its last sentence. The
   paragraph is complete when each sentence connects to the sentence before
   it, each join states a real relation, and the sentence lengths differ: no
   row of short sentences and no row of long sentences remains (S14).
4. When you write from a source, compare the result with the facts in the
   source (`references/fidelity.md`).

### Audit

Someone asks you to check existing text. Read `references/audit.md` and follow
it. Short version: run `scripts/lint.py`, read the text for what the linter
cannot see, discard the false positives, report hard findings and soft advice
separately, and ask before you rewrite.

```bash
python3 skills/writing/first-read/scripts/lint.py path/to/file.md
```

Add `--soft` for advisory checks. Select the profile with `--profile
procedural` for a runbook or a procedure, and with `--profile casual` for a
post or an email. Run the linter with `--soft` on your own draft too, because
the S14 check finds a row of short sentences and a row of long sentences.

## The rules in one screen

Hard, always:

no semicolons (H1) - active voice (H2) - no stacked auxiliaries (H3) - simple
tenses only (H4) - no "-ing" outside a noun (H5) - no phrasal verbs (H6) -
imperative for instructions (H7) - one instruction per sentence (H8) - condition
first, then a comma (H9) - notes inform only (H10) - warnings state the
consequence (H11) - no contractions outside the casual profile, no dropped
words (H12) - vertical lists for
complex text (H13) - articles before nouns (H14) - three words maximum in a noun
cluster (H15) - one term for one thing (H16) - no uppercase prose (H17) -
gender-neutral language (H18)

Soft, with judgment: sentence length about 20 words in a procedure and 25 in a
description - one topic in each sentence and in each paragraph - the plain word
over the elaborate one - a verb instead of a noun built from a verb - connecting
words inside a sentence and between related sentences - a pronoun when only one
antecedent is possible - a varied rhythm with no row of short sentences and no
row of long sentences - no AI tells (T1 to T13).

One topic is a claim together with its reason, its condition, or its result.
Those parts share a sentence. Two separate claims are two sentences.

Fidelity, always in a rewrite: keep every fact (F1) - keep each degree of
certainty (F2) - keep exact values exact (F3) - add nothing (F4) - do not make
a statement more exact than the source (F5) - report a contradiction (F6)

## What this rule set will not do

Read the anti-goals in `references/soft-targets.md` before you apply the soft
targets. The short version:

- It will not fragment a sentence that holds one idea to reach a word count,
  and it will not write a paragraph as a row of short sentences.
- It will not join two separate claims to make a sentence longer.
- It will not change a fact, a number, or a degree of certainty to make a
  sentence shorter.
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
Read the `NOTICE.md` file next to this file before you redistribute anything.
