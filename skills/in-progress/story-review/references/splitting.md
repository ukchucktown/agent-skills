# Split patterns

Read this when a `size`, `atomic`, `closed`, or `estimable` finding needs a
next action. Name one pattern and say in one sentence what kind of first slice
it gives. Leave the choice of slice and the new stories to the author.

Unrelated capabilities joined in one story need no pattern: the next action is
one story for each capability. An `estimable` finding uses "Break out a
spike" only when the unknown needs an investigation. An unknown that a person
can decide needs that decision, not a spike.

A good split gives slices that each work end to end and each deliver something
a person can use. Prefer a split that lets the customer postpone or drop a
low-value slice (Lawrence). Split along business lines and scenarios, never by
technical layer (North. Cohn Ch. 7 "Slice the Cake").

| Pattern | Fits when |
|---|---|
| Workflow steps | The story covers a multi-step workflow. First slice: the simplest path from start to end. Later slices add the middle steps. |
| Operations | A verb such as "manage" hides several operations (create, read, update, delete). |
| Business rule variations | One capability applies several different business rules. |
| Variations in data | The complexity comes from kinds of data. First slice: one kind. |
| Data entry methods | The complexity is in the interface. First slice: the simplest input method. |
| Major effort | Most of the work falls on whichever variant comes first. Split by variant and let the customer choose the first. |
| Simple/complex | "What about X?" questions keep growing the story. First slice: the simplest version. Each variation becomes its own story. |
| Defer performance | "Make it work" can come before "make it fast". State the deferred target so it is not lost. |
| Break out a spike | The team cannot estimate because of an unknown. A timeboxed investigation answers named questions first. A last resort. |

Pattern names and conditions: Lawrence. Cohn Ch. 2 "Splitting Stories" also
covers the spike and warns that a split by layer gives parts that help nobody
alone. Cohn Ch. 2 "Combining Stories" covers the opposite case: very small
related items can become one story.
