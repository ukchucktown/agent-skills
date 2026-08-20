# First Read

A writing rule set for technical prose, adapted for software from ASD-STE100
Simplified Technical English, Issue 9.

The name is the goal. A reader understands the text on the first read and does
not go back. That includes a reader whose first language is not English, and it
includes an agent that consumes the text later.

It ships in three forms:

| Form | Path | Use it for |
|---|---|---|
| Agent skill | `skills/first-read/` | Authoring and auditing in any agent that reads skills, invoked with `/first-read` |
| Claude Code output style | `output-styles/first-read.md` | The hard rules on every deliverable, with no invocation |
| Portable prompt | `PROMPT.md` | Any other agent harness: Cursor, an SDK, an `AGENTS.md` |

Scope: prose that another person reads later. Issues, PR descriptions, commit
messages, specs, RFCs, ADRs, docs, release notes, runbooks, and explanations.
Code is out of scope. Conversational replies are out of scope.

## Install

The skill installs with the [`skills`](https://github.com/vercel-labs/skills)
CLI, which supports Claude Code and about seventy other agents:

```bash
npx skills add ukchucktown/first-read --global --agent claude-code --copy --yes
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

The output style is not a skill, so the CLI does not install it. Copy the one
file:

```bash
mkdir -p ~/.claude/output-styles
cp output-styles/first-read.md ~/.claude/output-styles/
```

Requirements: Node 18 or later for the CLI, Python 3.8 or later for the linter.
The linter has no dependency.

## Activate the output style

The copy places the file. It does not select it. Do one of these:

- Run `/config` in the terminal and pick "First Read" under **Output style**.
- Add the field to `.claude/settings.local.json` in your project:

  ```json
  { "outputStyle": "First Read" }
  ```

The desktop app has no `/config` menu. Edit the settings file, or open
**Settings > Claude Code**.

Claude Code reads the system prompt once at session start, so run `/clear` or
start a new session.

## Use

**Author.** With the output style active, the 18 hard rules apply to every
deliverable. Without it, invoke `/first-read`.

**Audit.**

```bash
python3 skills/first-read/scripts/lint.py docs/upgrade.md --soft
```

The linter reports hard findings first and soft advice second. Each line gives
a location, a rule, and a fix. Use `--profile procedural` for a runbook, and
`--json` for a machine-readable result. The exit code is 1 when there is a hard
finding, so the linter works in a pre-commit hook or in CI.

**Another harness.** Give `PROMPT.md` to the agent as a system prompt, a Cursor
rule file, or a section of an `AGENTS.md`. The file is self-contained, refers to
no other file, and costs about 6000 tokens. Cut the word-swap appendix for a
smaller prompt.

## How the pieces fit

```
skills/
  first-read/              the layout the skills CLI discovers
    SKILL.md               entry point: the scope test and the two modes
    references/
      hard-rules.md        18 mechanical rules, each with software examples
      soft-targets.md      13 targets, and the 8 anti-goals that keep them safe
      word-swaps.md        about 230 swaps, and the domain words to keep
      artifacts.md         2 profiles, and a note for each artifact type
      audit.md             the check procedure and the report format
    scripts/lint.py        checker for the mechanical rules
output-styles/
  first-read.md            the hard tier only, always in context
PROMPT.md                  generated bundle for other harnesses
scripts/
  build_prompt.py          output style plus references, to PROMPT.md
  test_lint.sh             self-test for the linter
tests/fixtures/            compliant and non-compliant text
NOTICE.md                  provenance, and the redistribution boundary
```

The directory is `skills/first-read/` because the `skills` CLI walks `skills/`
and treats each child that holds a `SKILL.md` as one skill. The layout also
leaves room for a second skill later.

Who reads what:

- The **output style** holds the hard tier and nothing else. It stays in context
  every turn, so it must stay small.
- The **skill** holds everything that needs judgment or a lookup. It loads on
  demand. `SKILL.md` tells the agent to skip `hard-rules.md` when the output
  style is already active, so the rules never load two times.
- **`PROMPT.md`** is generated from the same two sources, so the three forms
  cannot drift.

## Two tiers

**Hard rules** are mechanical. They need no judgment about meaning, and they are
safe on every sentence.

The ID is ours. It appears in linter output and in `hard-rules.md`. The last
column gives the rule number in Part 1 of ASD-STE100, Issue 9, so that you can
compare our rule with the rule there. A number such as `3.5` is a numbered
rule. `GR-7` is a general recommendation, which the specification lists after
rule 9.4 rather than as a numbered rule. `ours` marks a rule with no equivalent
in the specification.

| ID | Rule | ASD-STE100 |
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
| H17 | No uppercase prose | ours |
| H18 | Gender-neutral language | GR-7 |

We do not reproduce the text of any of these rules. Read a copy of the
specification for that.

**Soft targets** need judgment: sentence length, paragraph shape, word choice,
connecting words, pronoun clarity, American spelling. They are targets. Meaning
always wins.

Read the anti-goals in `skills/first-read/references/soft-targets.md` before you
apply a
target. They exist because these targets are the ones that damage text when a
writer applies them without thought. The first anti-goal is the important one:
do not split a sentence that holds one idea to reach a word count.

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
| Scope | Deliverables only | An output style colors every turn. Without a scope test it clips the agent's own replies to 25 words |

## Claude Code specifics

- The output style sets `keep-coding-instructions: true`. Without that field, a
  custom output style leaves out Claude Code's built-in software engineering
  instructions, such as how to scope changes, write comments, and verify work.
- An output style reaches the main conversation only. A subagent runs its own
  system prompt, so a subagent must read
  `skills/first-read/references/hard-rules.md` itself, or receive `PROMPT.md`. A fork is the exception, because it inherits
  the full system prompt of the parent.
- A change of output style invalidates the prompt cache.
- The skill description lists "pte", "STE", and "in plain technical English" as
  trigger phrases, so the earlier names still reach the skill.

## Development

```bash
./scripts/test_lint.sh              # 18 assertions: fixtures, and our own prose
python3 scripts/build_prompt.py     # rebuild PROMPT.md after a reference edit
npx skills add . --agent claude-code --yes   # install this working copy
```

The last command symlinks, so an edit here reaches the installed skill at once.
Add `--copy` when you want a snapshot instead.

`PROMPT.md` is generated. Never edit it by hand.

The repository obeys its own rules, and the self-test asserts that every prose
file here passes the hard tier. A new rule therefore needs four edits:
`hard-rules.md` or `soft-targets.md`, the output style when the rule is hard,
`lint.py` when the rule is mechanical, and a fixture in `tests/fixtures/`.

The fixture counts in `scripts/test_lint.sh` are exact. A drop in the
`violations.md` count means that a check no longer works. A rise in the
`compliant.md` count means a new false positive.

## Provenance

The rules are adapted and the wording is original. A rule number such as
`(3.5)` cites ASD-STE100 Issue 9 so that anyone can compare a rule with its
source. The citations are references, not quotations.

This repository holds no part of that specification. The specification, any
extraction of it, and the script that produced our extraction all live outside
this repository, because they belong to the Aerospace, Security and Defence
Industries Association of Europe (ASD). `.gitignore` keeps a guard against a
file of either kind.

This project is not an ASD product. ASD does not endorse it. Read `NOTICE.md`
for the full statement.
