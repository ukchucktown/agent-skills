# Consumer loses records after a crash

The consumer commits the offset before it writes the record. A crash between
those two operations advances the offset and loses the record.

Warning: Do not run the repair script against production. The script truncates
the events table, and you cannot recover the data.

Steps to reproduce:

1. Start the consumer.
2. Stop the process after the commit.
3. Read the audit table. The record is absent.
