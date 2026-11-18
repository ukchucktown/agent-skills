# Fidelity rules

These rules apply when you rewrite text, and when you write from source
material such as a diff, a log, a thread, or a set of notes. They are hard
rules. A rewrite that reads well and changes a fact is a defect.

The rules exist because the other rules create pressure. A split sentence can
lose its qualifier, and an edit for an AI tell can remove a claim together with
its decoration.

---

## F1 - Keep every fact

Each claim, condition, warning, and exception in the source stays in the
result. When a fact does not fit the sentence, change the sentence.

- Source: The job retries three times, except on a 4xx response.
- No: The job retries three times.
- Yes: The job retries three times. A 4xx response stops the retries.

## F2 - Keep each degree of certainty

A qualifier such as "can", "probably", "in most cases", or "we think" carries
information. Keep it in some form, at the same strength.

- Source: The patch might fail on version 2.
- No: The patch fails on version 2.
- Yes: The patch can fail on version 2.

One qualifier is sufficient for one claim. Remove a second qualifier only when
it repeats the first one (T7).

## F3 - Keep exact values exact

Numbers, units, names, dates, versions, quoted text, and identifiers stay as
the source gives them.

- Source: The table has 40+ columns.
- No: The table has about 40 columns.
- Yes: The table has 40+ columns.

## F4 - Add nothing

Do not add a fact, an example, a reason, a source, or a warning that the source
does not give. When the text needs a fact that you do not have, ask for it, or
mark the gap in a note to the person.

- Source: The deploy failed.
- No: The deploy failed because of a network error.

## F5 - Do not make a statement more exact than the source

When the source is vague, the result stays vague. Do not replace a loose
relation with a cause, and do not expand a term that the source does not
define.

- Source: The outage is related to the DNS change.
- No: The DNS change caused the outage.
- Yes: The outage is related to the DNS change. (Then ask the person how.)

## F6 - Report a contradiction

When two statements in the source disagree, keep both statements and tell the
person. Do not select one.

---

## Procedure

1. Before you rewrite, list the facts: each claim, number, name, date,
   condition, warning, and degree of certainty.
2. After you rewrite, compare the result with the list. The rewrite is complete
   when each item on the list is in the result at the same strength, and the
   result has no item that is not on the list.

Examine these edits first, because they lose facts most often: a split
sentence, a list of three that became two (T5), a removed qualifier (T7), and
a list with bold labels that became prose (T10).
