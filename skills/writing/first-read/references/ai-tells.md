# AI tells

An AI tell is a habit that a reader recognizes as machine writing. Each tell
adds words and adds no claim. A reader who sees two or three tells trusts the
text less, so the facts in the text lose their effect.

These are soft targets. When you write, state the claim that the tell replaces.
When you audit, report a tell as advice (anti-goal 8).

A tell marked "weak alone" is also a normal choice of a careful writer. Act on
it only when other tells are near it. Act on every other tell at the first
occurrence.

Each fix must obey the fidelity rules in `fidelity.md`. The fact below a tell
is usually correct, so keep the fact and remove only the decoration.

---

## T1 - A contrast with a claim that nobody made

The pattern is "not X but Y", "not only X but also Y", or the same contrast
across two sentences. The negative half names a view that no reader holds, and
its only function is to make the positive half sound larger. State the
positive half. Keep the contrast when the reader really believes X.

- No: This is not only a faster build tool, it is a new way to think about
  the pipeline.
- Yes: The build tool caches each step, so a rebuild after a small change
  takes 4 s.
- Keep: The flag does not disable retries. It disables only the backoff.

## T2 - A closer that repeats, and a row of fragments

A one-line paragraph at the end restates the paragraph before it. A row of
fragments ("No setup. No config.") does the same work with a drumbeat. Remove a
closer that adds no fact. Join the fragments into one sentence that makes a
claim (S14).

- No: We moved the API to edge workers. Latency dropped to 40 ms. No cold
  starts. No regions. That is the real win.
- Yes: We moved the API to edge workers. Latency dropped to 40 ms and cold
  starts stopped, because the code now runs in every region.

## T3 - A run-up before the point

The text announces a point before it makes the point: "Here is what you need to
know", "It is important to note that", "The key insight is". Remove the
announcement and start with the point.

- No: It is important to note that the API has a rate limit.
- Yes: The API permits 100 requests each minute for each key.

## T4 - A defense against an objection that nobody made

The text answers a critic who does not exist: "To be clear", "This is not to
say", "You might think". Remove the defense. Keep an objection that a person in
the thread really made.

- No: To be clear, this does not mean that microservices are bad. We split the
  billing service first.
- Yes: We split the billing service first.

## T5 - A group of three by habit

Three adjectives or three parallel examples appear because three sounds
complete. Keep three items only when the subject has three parts. When the
list states real features or values, keep its content (F1).

- No: The new dashboard is fast, intuitive, and powerful.
- Yes: The new dashboard loads in less than 1 s and shows all alerts on one
  page.

## T6 - A dash as a connecting word (weak alone)

An em dash or a spaced hyphen joins two clauses and does not say how they
relate. The semicolon has the same defect (H1). Use a connecting word, a colon,
parentheses, or a period.

- No: The migration — which took six weeks — is complete.
- Yes: The migration took six weeks and is complete.

## T7 - Stacked qualifiers (weak alone)

Two or three qualifiers protect one claim: "could potentially", "might in some
cases", "may possibly". Keep one qualifier, at the strength that the source
supports (F2).

- No: This change could potentially cause some problems in certain cases.
- Yes: This change can break requests that have empty headers.

Write the second form only when the source names the failure (F4).

## T8 - Stock words

Models use some words much more often than people do: "delve", "robust",
"seamless", "crucial", "pivotal", "showcase", "underscore", "comprehensive",
"landscape", "tapestry", "testament", "meticulous". Use the plain word, or
state the measured property that the stock word replaces. `word-swaps.md` has
the plain forms.

- No: The SDK has a robust and seamless cache layer.
- Yes: The SDK caches API responses on the device, and the cache survives a
  restart.

## T9 - Inflated importance

A normal fact becomes a turning point, a commitment, or a promise about the
future. The signs are sales words ("powerful", "world-class"), a clause that
states a significance ("which shows our commitment to quality"), and a verb
phrase in place of "is" or "has" ("serves as", "stands as", "boasts"). State
what the thing is and what it does.

- No: Version 2.0 is a pivotal release that shows a broader change in
  direction.
- Yes: Version 2.0 adds a CLI and removes support for Node 16.
- No: The `config/` folder serves as the central hub for settings.
- Yes: The `config/` folder holds the settings.

## T10 - Decoration in the format

Every list item starts with a bold label and a colon, or a heading has emoji,
title case, or a slogan. Remove the bold, and write prose when the labels add
nothing. Keep bold for a warning, an interface label, or a term that the
reader must find again. A heading names the content of its section.

- No: **Performance:** The release improves performance.
- Yes: The release decreases the page load time from 3 s to 1 s.
- No: Getting Started With The CLI
- Yes: Install the CLI

## T11 - Chat residue

A greeting, praise, an offer, or a closing line from a conversation stays in a
text that must stand alone: "Great question", "I hope this helps", "Let me know
if", "Here is the updated version". Remove the wrapper and keep the content.

- No: Here is a summary of the change. I hope this helps!
- Yes: (Start with the summary.)

## T12 - Text about the document

The text describes itself or its history in place of its subject: "This
section describes", "The table below compares", "This function replaces the old
loop". Write about the subject. A change log, a migration guide, and a PR
description are the correct places for history.

- No: This function replaces the old approach, which examined every user.
- Yes: This function finds a user in a hash map, so each lookup is O(1).

## T13 - Context that the reader already has

A reply restates the problem, repeats the diagnosis, and shows the evidence
before it reaches the decision. Apply this target to a reply in a thread, such
as a review comment or an issue comment. Start with the decision, then give
only the facts that the reader does not have.

- No: You are correct that the cron job fails on the first day of the month. I
  examined the job, and it uses the local time zone, and I tested three dates.
  So I think that UTC is the correct fix.
- Yes: Agreed. I will change the job to UTC. The local time zone breaks the
  date calculation on the first day of the month.
