# Audit procedure

Use this when someone asks you to check text that already exists.

## Procedure

1. **Get the text.** A file path, a range of lines, a pasted block, or a diff.
   When the target is a whole repository, ask which files. Do not audit
   everything by default.

2. **Decide the profile.** Read `artifacts.md`. A document with a procedure in
   it has two profiles. Record which sections are procedural.

3. **Run the linter.**

   ```
   python3 skills/writing/first-read/scripts/lint.py <path>...
   ```

   Add `--soft` for the advisory checks. Add `--profile procedural` when the
   whole file is a procedure. The linter finds the mechanical violations. It
   does not find every one, and it does not judge meaning.

4. **Read the text yourself** for what the linter cannot see:

   - Passive voice. The linter reports it as advice only, because rule 3.6
     permits an agentless passive in descriptive text. You decide (H2).
   - A phrasal verb that is not in the linter's list (H6).
   - A note that gives an instruction or a limit (H10).
   - A warning with no stated consequence (H11).
   - A term that changes halfway through the document (H16).
   - A paragraph with two topics (S3).
   - A pronoun that could point at two things (S10).
   - List punctuation: a comma or a semicolon at the end of an item (H13).

5. **Discard the false positives.** Check every finding against the anti-goals
   in `soft-targets.md`. A finding inside quoted text, a log line, an
   identifier, an error message, or an RFC 2119 keyword is not a finding.

6. **Report.** Use the format below.

7. **Ask before you rewrite.** Never rewrite someone's prose without their
   agreement. Offer the rewrite, or offer to fix one class of finding.

## Report format

Hard violations first, as a list. Each line gives the location, the rule, and
the fix.

```
Hard (must fix)
  docs/upgrade.md:14   H1  semicolon        -> two sentences
  docs/upgrade.md:22   H3  "has been applied" -> "we applied"
  docs/upgrade.md:31   H7  "you should run" -> "Run"
  docs/upgrade.md:48   H12 "don't"          -> "do not"

Soft (advice)
  docs/upgrade.md:9    S1  38 words, two ideas
  docs/upgrade.md:26   S4  "utilize" -> "use"
  docs/upgrade.md:52   S3  paragraph has 9 sentences

12 hard, 7 soft. Fix the hard findings?
```

Rules for the report:

- Group by tier. Never mix them.
- Give the fix, not only the rule. A finding without a fix is not useful.
- Count the findings at the end.
- When there are no hard findings, say so in one line. Do not pad the report.
- When a finding is arguable, leave it out. A report of 12 real findings is
  worth more than a report of 60 with 40 that are wrong.

## When the text is not yours to fix

Some text arrives from a source you must not change: a vendor document, a
customer report, a legal clause, a quoted specification. Audit it if asked, but
say in one line that the text cannot be changed, and report the findings as
information.
