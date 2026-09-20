# Hard rules

These rules are mechanical. They need no judgment about meaning, and they are
safe to apply to every sentence. Apply all of them.

Each rule cites its source rule in ASD-STE100 Issue 9. The citation is for
traceability. It is not a quotation.

Scope: prose that a reader other than the person in this conversation will read
later. Code is exempt. Conversational replies are exempt. In code comments,
these rules are guidance and never block a change.

---

## H1 - Do not use semicolons (8.1)

A semicolon joins two sentences that must be separate. Write two sentences.

- No: The job runs nightly; it writes to the audit table.
- Yes: The job runs nightly. The job writes to the audit table.

## H2 - Use the active voice (3.6)

The subject of the sentence does the action. Passive voice is permitted only in
descriptive text, and only when you do not know the agent.

- No: The token is validated by the gateway.
- Yes: The gateway validates the token.
- Permitted: During the deploy, the config was overwritten. (You do not know
  what overwrote it.)

Test for passive voice: ask "by whom or by what?" If the sentence answers that
question, or could, it is passive.

Four ways to remove it:

- Make the agent the subject. "A retry policy triggers the second call."
- Replace the empty verb with the real verb. "The scheduler reads these values"
  instead of "These values are used by the scheduler."
- In instructions, use the imperative. "Restart the broker."
- When no agent is given, use "you" for the reader or "we" for the team.

## H3 - Do not stack auxiliary verbs (3.4)

Do not build a verb from "have", "must be", "can be", "is to be", "will be" plus
a past participle. These constructions are long and usually passive.

- No: The migration has been applied.
- Yes: We applied the migration.
- No: The limit can be increased.
- Yes: You can increase the limit.
- No: The cache must be cleared first.
- Yes: Clear the cache first.
- No: The index will be rebuilt by the worker.
- Yes: The worker will rebuild the index.

## H4 - Use only these verb forms (3.2, 3.3)

- The infinitive: to retry
- The imperative: Retry the request.
- The simple present: The worker retries the request.
- The simple past: The worker retried the request.
- The simple future: The worker will retry the request.
- The past participle as an adjective: the retried request

Do not use the present perfect ("has retried"), the past perfect ("had
retried"), or any progressive form ("is retrying", "was retrying").

The past participle as an adjective is not passive voice. It shows a condition.
Use it before a noun, or after a form of "to be", "to become", or "to stay".

- Yes: Examine the failed jobs.
- Yes: When the queue is drained, restart the consumer.

## H5 - Use "-ing" words only inside a noun (3.5)

An "-ing" word can be a verb, an adjective, or a noun. That ambiguity produces
long sentences. Use an "-ing" word only as a technical noun, or as a modifier
inside a technical noun.

- Permitted as a noun: logging, caching, testing, monitoring, tracing, sharding
- Permitted as a modifier: connection pooling, rolling restart, load-balancing
  policy, streaming endpoint

Everywhere else, rewrite.

- No: When running the migration, take a snapshot first.
- Yes: Before you run the migration, take a snapshot.
- No: The service is failing on startup.
- Yes: The service fails on startup.
- No: Users reporting timeouts are on the old client.
- Yes: The users who report timeouts are on the old client.

## H6 - Do not use phrasal verbs (9.3)

A verb plus a preposition often means something different from its parts. Use
one exact verb instead.

- set up -> configure, install, create
- shut down -> stop
- spin up -> start, create
- roll out -> release, deploy
- turn on / turn off -> enable, disable
- figure out -> find, identify
- come up with -> propose, select
- look into -> examine, investigate
- end up -> become
- get rid of -> remove, delete
- back up (verb) -> keep "do the backup of", or use "copy"
- fall back -> use the fallback
- run into -> find, meet

Keep "log in", "log out", "sign in", and "sign out" when they name a product
action the reader sees in the interface.

## H7 - Write instructions in the imperative (5.3)

An instruction tells the reader to do something. Start with the verb.

- No: The config file should then be updated.
- Yes: Update the config file.
- No: You will need to restart the pod.
- Yes: Restart the pod.

Do not put "must" before an imperative unless the instruction prevents data
loss, a security problem, or an outage.

- No: You must then run the migration.
- Yes: Run the migration.
- Permitted: Warning: You must stop the writer before you run the migration.
  A concurrent write corrupts the index.

## H8 - Write one instruction in each sentence (5.2)

One step, one sentence. Number the steps.

- No: Stop the consumer and drain the queue, then restart it.
- Yes:
  1. Stop the consumer.
  2. Drain the queue.
  3. Start the consumer.

Two actions can share a sentence when they occur at the same time, or when the
second is the immediate result of the first.

- Yes: Hold the lock and write the checkpoint.
- Yes: Run the load test. The p99 latency must stay below 200 ms.

## H9 - Put the condition first, then a comma, then the command (5.4)

The reader must know the condition before the action.

- No: Restart the broker if the lag is more than 10000 messages.
- Yes: If the lag is more than 10000 messages, restart the broker.
- No: Apply the patch when the deploy window opens.
- Yes: When the deploy window opens, apply the patch.

The comma position changes the meaning. Read the sentence again after you move
it.

## H10 - Notes give information only (5.5)

A note must not contain an instruction, a requirement, or a limit. If the reader
must do something, it is a step. If the reader can cause damage, it is a
warning.

- No: Note: Make sure that the flag is off before you deploy.
- Yes (as a step): Make sure that the flag is off.
- No: Note: The timeout must not be more than 30 s.
- Yes (in the step): Set the timeout. The timeout must not be more than 30 s.
- Yes: Note: The first request after a deploy can take 2 s.

To test a procedure, read it without the notes. If a reader cannot complete it,
move that information into a step.

## H11 - Give safety information in three parts (7.1, 7.2, 7.3)

Use "Warning" for a risk of injury, of data loss, or of a production outage.
Use "Caution" for a risk of damage to a tool, a test environment, or local
state. When both apply, use "Warning".

Write the signal word, then the command or the condition, then the risk.

- No: Caution: care is required with this script.
- Yes: Warning: Do not run this script against production. The script truncates
  the events table and the data cannot be recovered.
- Yes: Caution: Before you run the seed task, stop the local worker. A running
  worker writes duplicate rows.

Always state the consequence. A warning without a consequence is ignored.

## H12 - Write every word (4.2)

Do not use contractions. Do not drop the subject, the verb, or the article.

- No: Can't reproduce. Fails on main.
- Yes: I cannot reproduce this. The test fails on main.
- No: If set, the flag disables retries.
- Yes: If the flag is set, the flag disables retries.
- No: Remove the lock and file.
- Yes: Remove the lock and the file.

## H13 - Put complex text in a vertical list (4.3)

When a sentence carries several items or several actions, use a list.

- Put a colon at the end of the sentence before the list.
- Start each item with an uppercase letter.
- Use an article before the noun that is the subject of each item.
- Put a period at the end of an item only when the item is a full sentence.
- Never put a comma or a semicolon at the end of an item.
- Put a period at the end of the last item.
- Make sure that each item connects to the text before the colon.
- Do not mix instructions and descriptions in one list.
- Do not nest a list inside a list. Use parentheses, or a second list at the
  same level.

In a list of prohibitions, repeat "Do not" in each item.

- No: Do not: use the admin token, share the log file.
- Yes: Obey these rules:
  - Do not use the admin token.
  - Do not share the log file.

## H14 - Use an article or a demonstrative before a noun (4.5)

- No: Update config file, then restart service.
- Yes: Update the config file, then restart the service.
- Yes: This document tells you how to rotate the key.

Do not use an article for a general concept, and do not use a definite article
before a name or an identifier.

- Yes: Timeouts cause retries. (A general statement.)
- Yes: This change increases throughput. (An abstract quality.)
- Yes: Restart pod api-7f3c. (Not "the pod api-7f3c".)

In a series, one article at the start means that the first adjective applies to
every item. Repeat the article when it does not.

- The new keys, tokens, and secrets (all of them are new)
- The new keys, the tokens, and the secrets (only the keys are new)

## H15 - Use a maximum of three words in a noun cluster (2.1, 2.2)

A long chain of nouns hides the relations between the words. The reader must
hold four modifiers in memory before the head noun arrives.

- No: request retry backoff policy configuration
- Yes: the configuration of the backoff policy for request retries
- No: Fix the user session token refresh failure.
- Yes: Fix the failure of the token refresh in user sessions.

When a term of more than three words is the official name of a thing, write it
in full the first time. Then do one of two things:

- Give a shorter form and use the shorter form after that.
- Use hyphens to bind the words that act as one unit.

- Yes: The Kafka consumer group rebalance protocol (referred to here as the
  "rebalance protocol") controls partition assignment.
- Yes: Set the read-replica failover timeout. (3 words. Hyphenated words count
  as one word.)

Do not hyphenate every word to defeat the limit.

- No: the read-replica-failover-timeout value
- Yes: the read-replica failover timeout

## H16 - Use one term for one thing (1.11, 9.4)

Choose a term and repeat it. Do not vary it for style. Varying the term makes
the reader ask whether you mean a different thing.

- No: The job writes to the audit table. The task retries on failure. The
  worker then commits.
- Yes: The job writes to the audit table. The job retries on failure. The job
  then commits.

The same applies to the wording of repeated actions. When two steps do the same
kind of thing, word them the same way.

## H17 - Do not write prose in uppercase (ours)

Aerospace manuals print their examples in uppercase. That is a print convention
of those manuals. It is not a rule, and it does not belong in an issue, a spec,
or a document. Write signal words as "Warning:" and "Caution:", not "WARNING:".

Keep uppercase only where the text is quoted from an interface, an environment
variable, a constant, or a log line.

## H18 - Use gender-neutral language (GR-7)

Do not use "he" or "she" for a person whose pronouns you do not know. Use
"they", or name the role.

- No: When the reviewer approves, he merges the branch.
- Yes: When the reviewer approves, they merge the branch.
- Yes: The reviewer approves the change and then merges the branch.
