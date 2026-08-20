#!/usr/bin/env python3
"""Plain technical English linter.

Checks the mechanical rules only. It cannot judge meaning, so it cannot check
H2 (active voice with no "by"), H10 (notes that instruct), H11 (a warning with
no consequence), H15 (noun clusters), or H16 (one term for one thing). Read the
text for those.

No dependencies. Python 3.8 or later.

Usage:
    python3 lint.py FILE [FILE ...]
    python3 lint.py --soft FILE
    python3 lint.py --profile procedural FILE
    python3 lint.py --json FILE

Exit code 1 when there is a hard finding, 0 otherwise.
"""

import argparse
import bisect
import json
import re
import sys

# --------------------------------------------------------------------------
# Masking. Text we must never lint: fenced code, inline code, URLs, markdown
# link targets, quoted strings, and RFC 2119 keywords.
# --------------------------------------------------------------------------

MASK_PATTERNS = [
    re.compile(r"^(?P<b>[ \t]*(?:```|~~~)).*?^[ \t]*(?:```|~~~)[ \t]*$",
               re.S | re.M),          # fenced code
    re.compile(r"^(?: {4}|\t)\S.*$", re.M),   # indented code
    re.compile(r"`[^`\n]+`"),                 # inline code
    re.compile(r"<[^>\n]+>"),                 # html / autolink
    re.compile(r"\]\([^)\n]*\)"),             # markdown link target
    re.compile(r"\b[a-z][a-z0-9+.-]*://\S+"), # bare url
    re.compile(r"\"[^\"]{0,200}?\"", re.S),   # quoted text, may wrap
    re.compile(r"“[^”]{0,200}?”", re.S),
    re.compile(r"\b(?:MUST NOT|MUST|SHALL NOT|SHALL|SHOULD NOT|SHOULD|MAY|"
               r"REQUIRED|RECOMMENDED|OPTIONAL)\b"),  # RFC 2119
    re.compile(r"^\s*(?:\||\+[-=+]).*$", re.M),  # table rows and rules
    re.compile(r"^---+$", re.M),
    re.compile(r"\A---\n.*?\n---\n", re.S),        # yaml frontmatter
    # Lines that deliberately show what not to write.
    re.compile(r"^[ \t]*[-*]?[ \t]*(?:No|Non-STE|Not|Weak|Too long|Too dense|"
               r"Instead of|Do not write|Incorrect|Wrong|Before|Bad)[ \t]*:.*$",
               re.M),
    # Any line that maps one form to another is a mapping, not prose.
    re.compile(r"^.*(?:->|→).*$", re.M),
]


def mask(text):
    """Blank out spans we must not lint, keeping every offset stable."""
    out = list(text)
    for pat in MASK_PATTERNS:
        for m in pat.finditer(text):
            for i in range(m.start(), m.end()):
                if out[i] != "\n":
                    out[i] = " "
    return "".join(out)


def line_index(text):
    return [i for i, c in enumerate(text) if c == "\n"]


def line_of(nl_positions, offset):
    return bisect.bisect_left(nl_positions, offset) + 1


# --------------------------------------------------------------------------
# Hard checks. Each entry: (rule, regex, message, fix or None)
# --------------------------------------------------------------------------

PHRASALS = {
    "set up": "configure, install, create",
    "sets up": "configures, installs, creates",
    "setting up": "configuring, installing",
    "shut down": "stop",
    "shuts down": "stops",
    "spin up": "start, create",
    "spins up": "starts, creates",
    "roll out": "release, deploy",
    "rolls out": "releases, deploys",
    "turn on": "enable",
    "turn off": "disable",
    "turns on": "enables",
    "turns off": "disables",
    "figure out": "find, identify",
    "figures out": "finds, identifies",
    "come up with": "propose, select",
    "comes up with": "proposes, selects",
    "look into": "examine, investigate",
    "looks into": "examines, investigates",
    "end up": "become",
    "ends up": "becomes",
    "get rid of": "remove, delete",
    "gets rid of": "removes, deletes",
    "fall back on": "use the fallback",
    "falls back on": "uses the fallback",
    "run into": "find, meet",
    "runs into": "finds, meets",
    "carry out": "do",
    "carries out": "does",
    "point out": "show, state",
    "points out": "shows, states",
    "take care of": "handle, do",
    "put out": "extinguish, publish",
    "give off": "release",
    "go through": "read, examine",
    "hook up": "connect",
    "back off": "decrease, wait",
    "check out": "examine",
    "sort out": "correct, resolve",
    "top off": "fill",
    "hold off": "wait, prevent",
}

# "-ing" words permitted as technical nouns or as modifiers in one.
ING_OK = {
    "logging", "caching", "testing", "monitoring", "tracing", "sharding",
    "polling", "batching", "throttling", "pooling", "streaming", "routing",
    "profiling", "debugging", "linting", "packaging", "shipping", "handling",
    "onboarding", "offboarding", "provisioning", "versioning", "indexing",
    "hashing", "encoding", "decoding", "parsing", "rendering", "scaling",
    "sampling", "buffering", "queueing", "queuing", "locking", "chunking",
    "training", "tuning", "embedding", "prompting", "grounding", "learning",
    "warning", "engineering", "accounting", "marketing", "meaning", "morning",
    "opening", "lighting", "servicing", "mating", "missing", "remaining",
    "during", "something", "nothing", "anything", "everything", "building",
    "setting", "settings", "ceiling", "string", "spring", "thing", "things",
    "ring", "bring", "king", "wing", "swing", "sing", "using",
    "following", "existing", "leading", "trailing", "pending", "outstanding",
    "rolling", "blocking", "non-blocking", "breaking", "corresponding",
    "underlying", "incoming", "outgoing", "ongoing", "upcoming",
    "auditing", "authoring", "reporting", "writing", "formatting", "naming", "wording",
    "numbering", "tooling", "tracking", "reviewing", "reasoning", "wrapping",
    "spacing", "spelling", "heading", "headings", "listing", "listings",
}

# The possessive "'s" is permitted (GR-8), so it is not in this pattern.
CONTRACTIONS = re.compile(
    r"\b(?:can|don|doesn|didn|won|wouldn|shouldn|couldn|isn|aren|wasn|weren|"
    r"hasn|haven|hadn|ain|mustn|needn|shan)['’]t\b"
    r"|\b\w+['’](?:ll|re|ve|m)\b"
    r"|\b(?:it|that|there|here|what|who|he|she|let)['’]s\b"
    r"|\b(?:I|you|we|they|he|she|it)['’]d\b",
)

IRREGULAR = (
    "gone|done|seen|been|taken|given|written|driven|known|shown|thrown|grown|"
    "blown|flown|drawn|chosen|broken|spoken|frozen|forgotten|hidden|ridden|"
    "risen|fallen|eaten|beaten|bitten|built|sent|kept|left|lost|made|meant|"
    "met|paid|put|read|run|said|set|spent|told|understood|held|found|got|"
    "gotten|begun|become|come|cut|dealt|felt|hit|led|lit|shut|split|thought|"
    "brought|bought|caught|taught|sought|dropped|stopped|shipped|committed|"
    "merged|deployed|applied|removed|added|fixed|changed|updated"
)
# A participle: a word of four or more letters ending in "ed" or "en", or a
# known irregular form. This keeps "has one" and "is often" out of the results.
NOT_PART = (
    "often|open|even|when|then|between|children|women|men|listen|happen|token|"
    "golden|sudden|wooden|kitchen|screen|green|seven|eleven|oven|dozen|citizen|"
    "garden|burden|warden|soften|sharpen|widen|harden|frozen|often|olden|"
    "hyphen|oxygen|nitrogen|hidden|sullen|linen|siren|omen|amen"
)
PART = r"(?!(?:%s)\b)(?:\w{2,}(?:ed|en)|%s)" % (NOT_PART, IRREGULAR)

AUX_STACK = re.compile(
    r"\b(?:has|have|had)\s+(?:not\s+|never\s+|already\s+)?(" + PART + r")\b"
    r"|\b(?:must|can|could|will|would|should|may|might|shall)\s+(?:not\s+)?be\s+("
    + PART + r")\b"
    r"|\b(?:is|are|was|were)\s+to\s+be\b",
    re.I,
)

# A bare passive. Rule 3.6 permits it in descriptive text when the agent is
# unknown, so the linter cannot decide. Advisory only.
BARE_PASSIVE = re.compile(
    r"\b(?:is|are|was|were|be|been|being)\s+(?:not\s+)?(" + PART + r")\b",
    re.I,
)

PROGRESSIVE = re.compile(
    r"\b(?:am|is|are|was|were|be|been|being)\s+(?:not\s+|still\s+|also\s+)?(\w+ing)\b",
    re.I,
)

GERUND_CLAUSE = re.compile(
    r"\b(?:when|while|after|before|by|without|for|on|upon|through|instead\s+of|"
    r"in\s+addition\s+to|start|starts|started|stop|stops|stopped|avoid|avoids|"
    r"keep|keeps|consider|considers|finish|finishes)\s+(\w+ing)\b",
    re.I,
)

GENDERED = re.compile(r"\b(?:he|she|him|his|hers|himself|herself)\b")

WEAK_IMPERATIVE = re.compile(
    r"\byou\s+(?:should|need\s+to|will\s+need\s+to|have\s+to|must\s+then)\b"
    r"|\bit\s+is\s+recommended\s+that\b"
    r"|\bplease\s+(?:run|check|make|see|note|update|add|remove|set)\b",
    re.I,
)

# Three or more consecutive uppercase words. A "word" needs two or more
# letters, so a rule id such as "H1" or a flag such as "-P" is not prose.
CAPS_RUN = re.compile(
    r"(?:\b[A-Z]{2,}[A-Z0-9/&.-]*\b[ ,]+){2,}\b[A-Z]{2,}[A-Z0-9/&.-]*\b")
CAPS_SIGNAL = re.compile(r"\b(?:WARNING|CAUTION|NOTE|DANGER|IMPORTANT)\s*:")

HARD_SIMPLE = [
    ("H1", re.compile(r";"), "semicolon", "write two sentences"),
    ("H12", CONTRACTIONS, "contraction", "write the words in full"),
    ("H18", GENDERED, "gendered pronoun", 'use "they", or name the role'),
    ("H17", CAPS_SIGNAL, "uppercase signal word", 'write "Warning:" or "Caution:"'),
    ("H17", CAPS_RUN, "uppercase prose", "write in sentence case"),
    ("H7", WEAK_IMPERATIVE, "instruction is not imperative",
     "start the sentence with the verb"),
]

# --------------------------------------------------------------------------
# Soft checks
# --------------------------------------------------------------------------

SWAPS = {
    "utilize": "use", "utilise": "use", "utilizes": "uses",
    "leverage": "use", "leverages": "uses", "leveraging": "use",
    "facilitate": "help", "facilitates": "helps",
    "accomplish": "do", "accomplishes": "does",
    "commence": "start", "commences": "starts",
    "initiate": "start", "initiates": "starts",
    "terminate": "stop", "terminates": "stops",
    "cease": "stop", "ceases": "stops",
    "ensure": "make sure that", "ensures": "makes sure that",
    "verify": "make sure that", "verifies": "makes sure that",
    "ascertain": "make sure that", "confirm": "make sure that",
    "obtain": "get", "obtains": "gets", "acquire": "get", "acquires": "gets",
    "perform": "do", "performs": "does", "performed": "did",
    "provide": "give", "provides": "gives", "provided": "gave",
    "require": "is necessary", "requires": "is necessary",
    "modify": "change", "modifies": "changes",
    "alter": "change", "alters": "changes",
    "reduce": "decrease", "reduces": "decreases",
    "eliminate": "remove", "eliminates": "removes",
    "exceed": "be more than", "exceeds": "is more than",
    "comprise": "have", "comprises": "has",
    "incorporate": "include", "incorporates": "includes",
    "indicate": "show", "indicates": "shows",
    "demonstrate": "show", "demonstrates": "shows",
    "represent": "show", "represents": "shows",
    "determine": "find", "determines": "finds",
    "detect": "find", "detects": "finds",
    "locate": "find", "locates": "finds",
    "attempt": "try", "attempts": "tries",
    "assist": "help", "assists": "helps",
    "permit": "let", "permits": "lets",
    "prohibit": "prevent", "prohibits": "prevents",
    "additional": "more", "adequate": "sufficient", "acceptable": "permitted",
    "appropriate": "applicable", "approximately": "about",
    "compulsory": "mandatory", "conventional": "standard",
    "excessive": "too much", "erroneous": "incorrect",
    "faulty": "defective", "feasible": "possible",
    "significant": "important", "substantial": "large",
    "various": "different", "numerous": "many",
    "insufficient": "not sufficient", "improper": "incorrect",
    "properly": "correctly", "improperly": "incorrectly",
    "currently": "at this time", "presently": "at this time",
    "frequently": "often is fine; keep one of the two",
    "subsequently": "then", "previously": "before",
    "additionally": "also", "furthermore": "also",
    "however": "but", "nevertheless": "but", "therefore": "thus",
    "amount": "quantity", "usage": "use", "utilization": "use",
    "capability": "function", "limitation": "limit",
    "discrepancy": "difference", "methodology": "method",
    "functionality": "function", "shall": "must",
}

PHRASE_SWAPS = {
    "in order to": "to",
    "prior to": "before",
    "subsequent to": "after",
    "due to the fact that": "because",
    "in the event that": "if",
    "in the case of": "if",
    "at this point in time": "now",
    "with regard to": "about",
    "with respect to": "about",
    "a number of": "some, or the count",
    "the majority of": "most",
    "as well as": "and",
    "is able to": "can",
    "are able to": "can",
    "has the ability to": "can",
    "make use of": "use",
    "take into account": "consider",
    "in spite of": "although",
}

LATIN = re.compile(r"\b(?:e\.g\.|i\.e\.|etc\.|N\.B\.|viz\.|cf\.)|\bvia\b", re.I)
BRITISH = re.compile(
    r"\b\w*(?:behaviour|colour|organis|analys|initialis|normalis|licence|"
    r"centre|cancelled|labelled|modelled|travelled|catalogue|dialogue)\w*\b",
    re.I,
)
MISSING_THAT = re.compile(
    r"\b(?:make sure|makes sure|made sure|show|shows|showed|recommend|"
    r"recommends|know|knows|ensure|ensures)\s+(?:the|a|an|it|this|these|you|we|"
    r"they)\b",
    re.I,
)

# --------------------------------------------------------------------------
# Sentences and paragraphs
# --------------------------------------------------------------------------

SEGMENT = re.compile(r"\n[ \t]*\n"
                     r"|\n(?=[ \t]*(?:[-*+]|\(?\d+[.)]|[A-Za-z][.)])[ \t])")
SENT_END = re.compile(r"(?<=[.!?])\s+(?=[\"'(\[]?[A-Z0-9])|(?<=:)[ \t]*\n")
WORD = re.compile(r"[A-Za-z0-9][A-Za-z0-9'’./%-]*")
LIST_MARK = re.compile(r"^\s*(?:[-*+]|\(?\d+[.)]|[a-zA-Z][.)])\s+")
HEADING = re.compile(r"^\s*#{1,6}\s")
ORDERED = re.compile(r"^\s*(?:\(?\d+[.)]|[A-Za-z][.)])\s+")


def _lead(chunk):
    return len(chunk) - len(chunk.lstrip())


def sentences(text):
    """Yield (offset, text, is_list_item) for each sentence-like unit.

    A list item is always its own unit. A colon ends a sentence only at the end
    of a line, which is the vertical-list case in rule 8.4. A lone "1." or "A."
    marker is never a sentence.
    """
    segments = []
    pos = 0
    for m in SEGMENT.finditer(text):
        segments.append((pos, text[pos:m.start()]))
        pos = m.end()
    segments.append((pos, text[pos:]))

    for seg_offset, seg in segments:
        if not seg.strip():
            continue
        mark = LIST_MARK.match(seg)
        is_item = bool(mark)
        body = (" " * len(mark.group(0)) + seg[mark.end():]) if mark else seg
        pos = 0
        for m in SENT_END.finditer(body):
            chunk = body[pos:m.start()]
            if chunk.strip():
                yield seg_offset + pos + _lead(chunk), chunk.strip(), is_item
            pos = m.end()
        tail = body[pos:]
        if tail.strip():
            yield seg_offset + pos + _lead(tail), tail.strip(), is_item


def paragraphs(masked):
    """Yield (offset, text) for each block separated by a blank line."""
    pos = 0
    for m in re.finditer(r"\n[ \t]*\n", masked):
        chunk = masked[pos:m.start()]
        if chunk.strip():
            yield pos + (len(chunk) - len(chunk.lstrip())), chunk.strip()
        pos = m.end()
    tail = masked[pos:]
    if tail.strip():
        yield pos + (len(tail) - len(tail.lstrip())), tail.strip()


def word_count(sentence):
    body = LIST_MARK.sub("", HEADING.sub("", sentence))
    return len(WORD.findall(body))


# --------------------------------------------------------------------------
# Runner
# --------------------------------------------------------------------------

def check_file(path, profile, want_soft):
    try:
        raw = open(path, encoding="utf-8").read()
    except OSError as exc:
        return [], [], "cannot read %s: %s" % (path, exc)

    masked = mask(raw)
    nl = line_index(raw)
    hard, soft = [], []

    def add(bucket, rule, offset, what, fix):
        bucket.append({
            "file": path, "line": line_of(nl, offset),
            "rule": rule, "what": " ".join(what.split()), "fix": fix,
        })

    for rule, pat, what, fix in HARD_SIMPLE:
        for m in pat.finditer(masked):
            add(hard, rule, m.start(), "%s: %s" % (what, m.group(0).strip()[:40]), fix)

    for m in AUX_STACK.finditer(masked):
        add(hard, "H3", m.start(), 'stacked auxiliary: "%s"' % m.group(0).strip(),
            "use a simple tense, or make the agent the subject")

    for m in PROGRESSIVE.finditer(masked):
        if m.group(1).lower() not in ING_OK:
            add(hard, "H4", m.start(), 'progressive tense: "%s"' % m.group(0).strip(),
                "use the simple present or the simple past")

    for m in GERUND_CLAUSE.finditer(masked):
        if m.group(1).lower() not in ING_OK:
            add(hard, "H5", m.start(), '"-ing" outside a noun: "%s"' % m.group(0).strip(),
                "rewrite with a subject and a verb")

    low = masked.lower()
    for phrase, fix in PHRASALS.items():
        start = 0
        while True:
            i = low.find(phrase, start)
            if i < 0:
                break
            before = low[i - 1] if i else " "
            after = low[i + len(phrase)] if i + len(phrase) < len(low) else " "
            if not before.isalnum() and not after.isalnum():
                add(hard, "H6", i, 'phrasal verb: "%s"' % phrase, fix)
            start = i + 1

    if want_soft:
        for para_offset, para in paragraphs(masked):
            in_list = False
            count = 0
            for rel, sent, is_step in sentences(para):
                offset = para_offset + rel
                n = word_count(sent)
                in_list = in_list or is_step
                limit = 20 if (profile == "procedural" or is_step) else 25
                if n > limit:
                    add(soft, "S1", offset, "%d words (target %d)" % (n, limit),
                        "look for a second idea, and split there")
                count += 1
                if count == 7 and not in_list:
                    add(soft, "S3", offset,
                        "paragraph has more than six sentences",
                        "find the second topic and start a new paragraph")

        for m in WORD.finditer(masked):
            w = m.group(0).lower().strip(".,")
            if w in SWAPS:
                add(soft, "S4", m.start(), '"%s"' % w, SWAPS[w])
        for phrase, fix in PHRASE_SWAPS.items():
            start = 0
            while True:
                i = low.find(phrase, start)
                if i < 0:
                    break
                add(soft, "S4", i, '"%s"' % phrase, fix)
                start = i + 1
        for m in LATIN.finditer(masked):
            add(soft, "S8", m.start(), 'Latin abbreviation: "%s"' % m.group(0),
                "use English words")
        for m in BRITISH.finditer(masked):
            add(soft, "S11", m.start(), 'British spelling: "%s"' % m.group(0),
                "use American spelling")
        for m in BARE_PASSIVE.finditer(masked):
            add(soft, "H2", m.start(),
                'possible passive voice: "%s"' % m.group(0).strip(),
                "make the agent the subject, or keep it if the agent is unknown")
        for m in MISSING_THAT.finditer(masked):
            add(soft, "S7", m.start(), 'missing "that": "%s"' % m.group(0).strip(),
                'add the conjunction "that"')

    hard.sort(key=lambda f: (f["line"], f["rule"]))
    soft.sort(key=lambda f: (f["line"], f["rule"]))
    return hard, soft, None


def render(findings, title):
    if not findings:
        return []
    width = max(len("%s:%d" % (f["file"], f["line"])) for f in findings)
    lines = [title]
    for f in findings:
        loc = "%s:%d" % (f["file"], f["line"])
        fix = " -> %s" % f["fix"] if f["fix"] else ""
        lines.append("  %-*s  %-4s %s%s" % (width, loc, f["rule"], f["what"], fix))
    return lines


def main(argv=None):
    ap = argparse.ArgumentParser(description="Plain technical English linter")
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--soft", action="store_true",
                    help="also report the advisory checks")
    ap.add_argument("--profile", choices=["descriptive", "procedural"],
                    default="descriptive",
                    help="sentence-length target (default: descriptive, 25 words)")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args(argv)

    all_hard, all_soft, errors = [], [], []
    for path in args.paths:
        hard, soft, err = check_file(path, args.profile, args.soft)
        if err:
            errors.append(err)
            continue
        all_hard += hard
        all_soft += soft

    if args.json:
        print(json.dumps({"hard": all_hard, "soft": all_soft,
                          "errors": errors}, indent=2))
        return 1 if all_hard else 0

    out = []
    out += render(all_hard, "Hard (must fix)")
    if all_hard and all_soft:
        out.append("")
    out += render(all_soft, "Soft (advice)")
    for err in errors:
        out.append("error: " + err)
    if not all_hard:
        out.append("No hard findings.")
    if args.soft:
        out.append("")
        out.append("%d hard, %d soft." % (len(all_hard), len(all_soft)))
    else:
        out.append("")
        out.append("%d hard. Run with --soft for the advisory checks."
                   % len(all_hard))
    out.append("Not checked here: H10 notes that instruct, H11 warnings with "
               "no consequence,")
    out.append("H13 list punctuation, H15 noun clusters, H16 term consistency. "
               "H2 passive voice")
    out.append("is advisory only, because rule 3.6 permits it when the agent "
               "is unknown.")
    out.append("Read the text for those.")
    print("\n".join(out))
    return 1 if all_hard else 0


if __name__ == "__main__":
    sys.exit(main())
