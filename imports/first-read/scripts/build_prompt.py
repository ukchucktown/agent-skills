#!/usr/bin/env python3
"""Build PROMPT.md, the single-file bundle for other agent harnesses.

The bundle is generated. Never edit PROMPT.md by hand. Edit the output style or
the files in skills/first-read/references/, then run this script.

    python3 scripts/build_prompt.py

Use the bundle where a harness accepts only one blob of text: a Cursor rule
file, an AGENTS.md section, an SDK system prompt, or the system message of
another model.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STYLE = os.path.join(ROOT, "output-styles", "first-read.md")
REFS = os.path.join(ROOT, "skills", "first-read", "references")
OUT = os.path.join(ROOT, "PROMPT.md")

HEADER = """<!-- GENERATED FILE. Do not edit.
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

"""

FOOTER = """
---

## Provenance

Rules adapted from ASD-STE100 Simplified Technical English, Issue 9, which is
the property of the Aerospace, Security and Defence Industries Association of
Europe (ASD). "ASD-STE100" and "Simplified Technical English" are ASD
trademarks. This rule set is not an ASD product, and ASD does not endorse it.
The wording here is original. It is not a reproduction of the source text.
"""

# Cross-references that only make sense inside the skill.
REWRITES = [
    (r"Read `word-swaps\.md`\.", "Read the appendix on word swaps."),
    (r"`word-swaps\.md`", "the appendix on word swaps"),
    (r"`soft-targets\.md`", "the section on soft targets"),
    (r"`hard-rules\.md`", "the section on hard rules"),
    (r"`artifacts\.md`", "the section on profiles and artifact notes"),
    (r"`SKILL\.md`", "the scope test above"),
    (r"the scope test in the scope test above", "the scope test above"),
    (r"See H17\.", "See hard rule 17."),
    (r"\(H(\d+)\)", r"(hard rule \1)"),
    (r"\bH(\d+) -", r"Hard rule \1 -"),
]


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def strip_frontmatter(text):
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            return text[text.find("\n", end + 1) + 1:]
    return text


def demote(text, levels=1):
    """Push every markdown heading down so the bundle has one h1."""
    return re.sub(r"^(#{1,5}) ", lambda m: "#" * (len(m.group(1)) + levels) + " ",
                  text, flags=re.M)


def drop_section(text, heading):
    """Remove a heading and its body, up to the next heading of that level."""
    level = len(re.match(r"#+", heading).group(0))
    pat = re.compile(r"^%s$.*?(?=^#{1,%d} |\Z)" % (re.escape(heading), level),
                     re.S | re.M)
    return pat.sub("", text)


def rewrite(text):
    for pat, repl in REWRITES:
        text = re.sub(pat, repl, text)
    return text


def main():
    style = strip_frontmatter(read(STYLE)).strip()
    style = drop_section(style, "# More detail").strip()
    # The output style opens with a note about Claude Code frontmatter. A
    # generic bundle has no frontmatter, so replace that opening.
    style = re.sub(
        r"\AThis style governs.*?`keep-coding-instructions: true`\.\n",
        "These rules govern the prose you write into deliverables. They change\n"
        "nothing else about how you work.\n",
        style, flags=re.S)

    soft = read(os.path.join(REFS, "soft-targets.md"))
    artifacts = read(os.path.join(REFS, "artifacts.md"))
    swaps = read(os.path.join(REFS, "word-swaps.md"))

    # Each reference file starts with its own h1. Replace it with our numbering.
    soft = re.sub(r"^# .*$", "# 2. Soft targets", soft, count=1, flags=re.M)
    artifacts = re.sub(r"^# .*$", "# 3. Profiles and artifact notes",
                       artifacts, count=1, flags=re.M)
    swaps = re.sub(r"^# .*$", "# 4. Appendix: word swaps", swaps, count=1,
                   flags=re.M)

    parts = [
        HEADER,
        "# 1. Scope and the hard rules\n",
        demote(style),
        "\n---\n",
        soft.strip(),
        "\n---\n",
        artifacts.strip(),
        "\n---\n",
        swaps.strip(),
        FOOTER,
    ]
    bundle = rewrite("\n".join(parts))
    bundle = re.sub(r"\n{4,}", "\n\n\n", bundle)

    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(bundle)

    lines = bundle.count("\n") + 1
    print("wrote %s (%d lines, %.1f kB, about %d tokens)"
          % (os.path.relpath(OUT, ROOT), lines, len(bundle) / 1000.0,
             len(bundle) // 4))
    return 0


if __name__ == "__main__":
    sys.exit(main())
