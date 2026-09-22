# First Read

A writing rule set for technical prose, adapted for software from ASD-STE100
Simplified Technical English, Issue 9.

The name is the goal. A reader understands the text on the first read and does
not go back. That includes a reader whose first language is not English, and it
includes an agent that consumes the text later.

It ships as an Agent Skill at `skills/writing/first-read/`. A supported agent
loads the skill when a task matches its description or when you invoke
`/first-read`.

Scope: prose that another person reads later. Issues, PR descriptions, commit
messages, specs, RFCs, ADRs, docs, release notes, runbooks, and explanations.
Code is out of scope. Conversational replies are out of scope.

## Install

The skill installs with the [`skills`](https://github.com/vercel-labs/skills)
CLI, which supports Claude Code and about seventy other agents:

```bash
npx skills add ukchucktown/agent-skills --skill first-read --global --agent '*' --copy --yes
```

| Flag | Effect |
|---|---|
| `--copy` | Copy the files. Without it, the CLI symlinks them |
| `--global` | Install for the user. Use `--project` for one repository only |
| `--agent claude-code` | The target agent. Use `--agent '*'` for every agent it detects |
| `--yes` | Skip the prompts |
| `--list` | Show the skills in the repository and install nothing |

The repository is private, and the CLI uses the git authentication you already
have.

Other commands: `npx skills list`, `npx skills update first-read`, and
`npx skills remove first-read`.

Requirements: Node 18 or later for the CLI, Python 3.8 or later for the linter.
The linter has no dependency.

## Use

**Author.** Ask the agent to use First Read, or let the skill description match
the writing task.

**Audit.**

```bash
python3 skills/writing/first-read/scripts/lint.py docs/upgrade.md --soft
```

The linter reports hard findings first and soft advice second. Each line gives
a location, a rule, and a fix. Use `--profile procedural` for a runbook, and
`--json` for a machine-readable result. The exit code is 1 when there is a hard
finding, so the linter works in a pre-commit hook or in CI.

## How the pieces fit

```
skills/writing/first-read/
  SKILL.md                 entry point: the scope test and the two modes
  NOTICE.md                provenance and the redistribution boundary
  references/
    hard-rules.md          18 mechanical rules, each with software examples
    soft-targets.md        13 targets and the 8 anti-goals that keep them safe
    word-swaps.md          about 230 swaps and the domain words to keep
    artifacts.md           2 profiles and a note for each artifact type
    audit.md               the check procedure and the report format
  scripts/lint.py          checker for the mechanical rules
tests/first-read/
  run.sh                   self-test for the linter
  fixtures/                compliant and non-compliant text
```

The `skills` CLI finds the nested `SKILL.md` and installs First Read as an
independent skill. The skill loads its references only when a task needs them.

## Two tiers

**Hard rules** are mechanical. They need no judgment about meaning, and they are
safe on every sentence.

The **ID** is ours. It appears in linter output and in `hard-rules.md`.

The **cited rule** points into Part 1 of ASD-STE100, Issue 9, so that you can
compare our rule with the rule there. Part 1 numbers its rules as
`section.rule`, so `3.5` is the fifth rule of section 3, and the nine sections
cover these topics:

| Section | Topic |
|---|---|
| 1 | Words |
| 2 | Noun clusters |
| 3 | Verbs |
| 4 | Sentences |
| 5 | Instructions and steps |
| 6 | Explanations |
| 7 | Safety instructions |
| 8 | Punctuation, and how to count words |
| 9 | General practice |

Two values in that column are not rule numbers:

- `GR-7` is a general recommendation. Section 9 lists a small set of these
  after rule 9.4, and they are not numbered rules.
- `none` means the specification has no counterpart, and the rule is ours.

| ID | Rule | Cited rule |
|---|---|---|
| H1 | No semicolons | 8.1 |
| H2 | Active voice, with an agentless passive only in description | 3.6 |
| H3 | No stacked auxiliaries: "has been", "must be cleared" | 3.4 |
| H4 | Simple tenses only, and no progressive form | 3.2, 3.3 |
| H5 | An "-ing" word only inside a noun | 3.5 |
| H6 | No phrasal verbs: "set up", "shut down", "roll out" | 9.3 |
| H7 | Instructions in the imperative | 5.3 |
| H8 | One instruction in each sentence | 5.2 |
| H9 | The condition first, then a comma, then the command | 5.4 |
| H10 | Notes give information only | 5.5 |
| H11 | A warning states the consequence | 7.1, 7.2, 7.3 |
| H12 | No contractions and no dropped words | 4.2 |
| H13 | Complex text in a vertical list | 4.3 |
| H14 | An article or a demonstrative before a noun | 4.5 |
| H15 | Three words maximum in a noun cluster | 2.1, 2.2 |
| H16 | One term for one thing | 1.11, 9.4 |
| H17 | No uppercase prose | none |
| H18 | Gender-neutral language | GR-7 |

H17 is ours because the specification gives no rules for formatting. Rule 7.1
says so directly, and it points a writer at their own style guide instead. Every
safety example in the specification appears in uppercase, which is a print
convention of aerospace manuals rather than a rule, so we exclude it and say so.

We do not reproduce the text of any rule. The topic words above are ours. Read a
copy of the specification for the wording.

**Soft targets** need judgment: sentence length, paragraph shape, word choice,
connecting words, pronoun clarity, American spelling. They are targets. Meaning
always wins.

Read the anti-goals in
`skills/writing/first-read/references/soft-targets.md` before you apply a target.
They exist because these targets can damage text when a writer applies them
without thought. The first anti-goal is the important one: do not split a
sentence that holds one idea to reach a word count.

## What the linter checks

Mechanical checks: H1, H3, H4, H5, H6, H7, H12, H17, H18. With `--soft`, it
also reports sentence length, paragraph length, word swaps, Latin
abbreviations, British spellings, and a missing conjunction "that".

It cannot check these, and it says so in every report:

- H2 passive voice. Rule 3.6 permits an agentless passive in descriptive text,
  so the linter reports a bare passive as advice and you decide.
- H10 a note that instructs, H11 a warning with no consequence, H13 list
  punctuation, H15 noun clusters, H16 a term that changes halfway through.

The linter never lints these spans: fenced code, indented code, inline code,
URLs, markdown link targets, quoted text, table rows, YAML frontmatter, lines
marked as counter-examples, lines that map one form to another, and RFC 2119
keywords.

## Design decisions

| Decision | Choice | Why |
|---|---|---|
| Vocabulary | Guidance, not a closed dictionary | The source has 2195 approved words. Software writing needs "idempotent" and "backpressure". Rule 1.5 category 19 and rule 1.12 category 2 make our vocabulary legitimate, so `word-swaps.md` leads with a keep list |
| Strictness | Two tiers, labelled per rule | A model given a hard 25-word limit fragments good sentences. The tier tells it which lever it pulls |
| Source of truth | The skill, in plain markdown | The references use no Claude Code syntax, so other harnesses can read them |
| Wording | Original, with rule numbers as citations | ASD owns the specification text. The rule numbers are freely citable and let anyone compare a rule with its source |
| Profiles | Procedural and descriptive | The source splits itself the same way. A 20-word step and a 25-word explanation are different jobs |
| Name | Descriptive, not the trademark | "ASD-STE100" and "Simplified Technical English" are ASD trademarks |
| Scope | Deliverables only | The scope test keeps the rules out of conversational replies and code |

## Development

```bash
./tests/first-read/run.sh                     # fixtures and First Read prose
npx skills add . --skill first-read --agent '*' --yes
```

The last command symlinks, so an edit here reaches the installed skill at once.
Add `--copy` when you want a snapshot instead.

The repository obeys its own rules, and the self-test asserts that every prose
file in the skill passes the hard tier. A new rule can require three edits:
`hard-rules.md` or `soft-targets.md`, `lint.py` when the rule is mechanical, and
a fixture in `tests/first-read/fixtures/`.

The fixture counts in `tests/first-read/run.sh` are exact. A drop in the
`violations.md` count means that a check no longer works. A rise in the
`compliant.md` count means a new false positive.

## Provenance

The rules are adapted and the wording is original. A rule number such as
`(3.5)` cites ASD-STE100 Issue 9 so that anyone can compare a rule with its
source. The citations are references, not quotations.

This repository holds no part of that specification. The specification and any
extraction of it live outside this repository because they belong to the
Aerospace, Security and Defence Industries Association of Europe (ASD).

This project is not an ASD product. ASD does not endorse it. Read the skill's
`NOTICE.md` file for the full statement.
