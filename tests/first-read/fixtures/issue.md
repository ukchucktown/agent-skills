# Consumer advances the offset before the write completes

## Current behavior

The consumer commits the partition offset and then writes the record to the
audit table. A crash between those two operations advances the offset without
the record. The record never arrives, and no retry occurs.

We saw this three times in the last two weeks. Each time, the audit table lost
between 4 and 30 records.

## Expected behavior

The consumer writes the record first. The consumer then commits the offset. A
crash before the commit repeats the write, which the unique constraint on
`event_id` makes safe.

## Steps to reproduce

1. Start the consumer against the `audit-events` topic.
2. Send 100 records.
3. Stop the process with `SIGKILL` after the first commit.
4. Start the consumer again.
5. Count the rows in the audit table. The count is less than 100.

## Effect

The audit table is the source for the compliance report. A missing record makes
that report incorrect, and we cannot detect the gap from the table itself.
