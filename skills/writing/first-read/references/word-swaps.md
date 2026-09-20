# Word swaps

The source specification has a controlled dictionary of 2195 words. We do not
use a closed vocabulary. This file holds the part that pays: the words that
occur most often in software writing, and the plainer word to use instead.

## How to use this file

1. Swap the word only when the plainer word keeps the meaning. When it does not,
   keep your word. Rule 9.1 in the source makes the same point: a word-for-word
   replacement is often not sufficient, and a different sentence is the answer.
2. A swap is a soft target. Never report a missed swap as a violation.
3. Read "Words to keep" first. It protects the vocabulary of this domain.

---

## Words to keep

The source specification marks some of these words as not approved. It also
gives two categories that make them legitimate:

- Technical nouns, category 19, computer science and information and
  communication technology (rule 1.5).
- Technical verbs, category 2, computer processes and applications (rule 1.12).

Our subject field is software. These words are the correct terms for the things
they name. Do not swap them.

**Verbs:** abort, boot, build, cache, clear, click, close, copy, create, cut,
debug, delete, deploy, deselect, disable, download, drag, enable, encrypt,
enter, erase, filter, format, highlight, install, invalidate, load, log, manage,
merge, navigate, open, paste, press, process, reboot, refresh, reset, restart,
run, save, scroll, sort, store, tap, test, type, update, upgrade, upload,
validate, zoom

**Nouns:** API, application, attachment, backup, cache, case, cursor, database,
endpoint, field, file, interface, job, memory, metadata, network, operating
system, program, queue, request, response, schema, setting, state, token,
version

**Precise terms:** atomic, backpressure, cardinality, concurrent, consistent,
deterministic, idempotent, immutable, latency, quorum, race condition,
throughput

The general rule: when a word names a thing or an action exactly, and the
plainer word names it less exactly, the exact word wins.

---

## Verbs

| Instead of | Write |
|---|---|
| accomplish | do, complete |
| achieve, acquire, obtain, attain | get |
| adopt, employ, leverage, utilize | use |
| aggravate, augment, heighten | increase |
| allocate, assign | give |
| allow, permit | let |
| alter, amend, convert, modify, vary | change |
| arise, recur | occur |
| ascertain, assure, confirm, ensure, establish, insure, verify | make sure that |
| assist | help |
| attempt | try |
| avert, avoid, hamper, inhibit, prohibit | prevent |
| cease, discontinue, halt, interrupt, suspend, terminate | stop |
| check (a thing) | examine |
| check (a fact) | make sure that |
| commence, initiate | start |
| comprise, consist of, incorporate | have, contain |
| conduct, perform | do |
| deflect, displace, shift, slide | move |
| demonstrate, denote, display, register, represent, reveal | show |
| detach | disconnect, remove |
| detect, diagnose, discover, locate, spot, trace | find |
| determine | find, calculate, select |
| diminish, deplete, lessen, reduce, shorten | decrease |
| dispatch, relay, submit, transmit | send |
| eliminate, extract, purge, strip, withdraw | remove |
| exceed | be more than |
| fabricate, manufacture, render | make |
| facilitate | help, make easier |
| happen | occur |
| impact (as a verb) | affect, change |
| indicate | show, identify |
| induce, incur, produce, trigger | cause |
| insert, place | put |
| interconnect, join, couple, fasten, link | connect |
| maintain | keep, hold |
| mount, equip, refit | install |
| need | is necessary |
| required | necessary |
| require, requires | no single word replaces this verb, so rewrite the sentence: "Y is necessary for X" |
| observe, track, watch | monitor |
| omit, exclude | do not include |
| proceed, progress, resume | continue |
| provide | give, supply |
| rectify | correct |
| remain | stay |
| reposition | move, put |
| retain | keep |
| rotate | turn |
| uncouple, unplug | disconnect |

## Nouns built from verbs

Use the verb. Rule 3.7 in the source: a verb states an action more clearly than
a noun.

| Instead of | Write |
|---|---|
| the alignment of | align |
| an assessment, an evaluation | analyze, estimate |
| a calculation of | calculate |
| a comparison of | compare |
| on completion of | when you complete |
| the incorporation of | include |
| the installation of (as an act) | install |
| the modification of | change |
| the preparation of | prepare |
| the removal of | remove |
| the utilization of, usage | use |

## Other nouns

| Instead of | Write |
|---|---|
| accuracy | precision |
| action, stage | step |
| activity | task, work |
| amount | quantity |
| capability | function |
| characteristic | property, quality |
| conclusion | end, result |
| discrepancy | difference |
| evidence | indication, sign |
| factor | cause |
| finding | result |
| gap | space, distance |
| kind | type |
| limitation | limit |
| matter, substance | material |
| option | alternative |
| order | sequence |
| origin | source |
| portion | part |
| probability | risk |
| reading | indication |
| size | dimension |
| technique, way | method, procedure |
| transition | change |

## Adjectives

| Instead of | Write |
|---|---|
| acceptable | permitted, satisfactory |
| adequate, enough | sufficient |
| allowable, authorized, permissible, qualified | permitted, approved |
| appropriate, pertinent | applicable |
| complicated, difficult | not easy |
| compulsory, vital | mandatory |
| conventional | standard |
| critical | very important |
| erratic | irregular |
| excessive | too much, more than |
| false, improper, wrong | incorrect |
| faulty, poor, failed | defective, incorrect |
| feasible | possible |
| fundamental, serious, significant | important |
| inadvertent, unintentional | accidental |
| insufficient | not sufficient |
| intact | not damaged |
| operable | can operate |
| partial | not fully |
| precise | accurate |
| prescribed, specific | specified |
| similar | equivalent, almost the same |
| simultaneous | at the same time |
| unsafe, severe, harmful, detrimental | dangerous |
| various | different |
| visible | you can see |

## Adverbs

| Instead of | Write |
|---|---|
| badly, improperly | incorrectly |
| cautiously, closely | carefully |
| circa | approximately |
| currently, now | at this time |
| greatly | very much |
| just | only |
| often | frequently |
| once | one time |
| partially, partly | not fully |
| precisely | accurately |
| progressively | gradually |
| properly | correctly |
| repeatedly | again and again |
| separately | independently |
| simultaneously | at the same time |
| twice | two times |
| urgently, promptly | immediately |
| yet | at this time |

Delete these when they add nothing: actually, basically, essentially, really,
simply, very (when the word after it is already absolute).

## Prepositions, conjunctions, and connectives

| Instead of | Write |
|---|---|
| according to | refer to |
| as well as, in addition, furthermore | and, also |
| beyond | more than |
| however, nevertheless, whilst | but |
| instead of | as an alternative to |
| per | for each |
| therefore | thus |
| via | with, through |

## Wordy phrases

| Instead of | Write |
|---|---|
| a number of | some, many, or the count |
| at this point in time | now |
| due to, owing to | because of |
| in order to | to |
| in the case of, in the event that, provided that | if |
| prior to | before |
| subsequent to | after |
| the majority of | most |
| with regard to, with respect to | about, for |

## Modal verbs

The source dictionary replaces "shall" with "must", "may" with "can", and
"would" with "can". Apply that in prose.

- No: The consumer shall acknowledge the message.
- Yes: The consumer must acknowledge the message.

One exception. In a specification that uses RFC 2119 keywords, "MUST", "MUST
NOT", "SHOULD", "SHOULD NOT", and "MAY" carry defined meanings. Keep those
words and keep their case. Do not swap "MAY" for "can" in a normative
statement.
