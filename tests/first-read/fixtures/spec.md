# Audit event delivery

## 3. Write ordering

3.1. The consumer MUST write the record to the audit table before it commits
the partition offset.

3.2. The audit table MUST have a unique constraint on `event_id`.

3.3. A repeated write of the same `event_id` MUST NOT create a second row. The
write is idempotent.

3.4. The consumer SHOULD commit the offset in the same batch interval as the
write. A longer interval increases the number of repeated writes after a crash.

3.5. The consumer MAY buffer up to 500 records before it writes. A larger
buffer increases the loss window, and this specification sets no upper limit.

## 4. Failure handling

Caution: Do not disable the unique constraint to increase write throughput.
Without the constraint, a repeated write creates a duplicate row, and the
compliance report then counts the event two times.

4.1. If the write fails, the consumer MUST NOT commit the offset.

4.2. If the write fails three times, the consumer MUST stop and emit a
`consumer.write.failed` metric.

Note: The metric has a 60 s scrape interval. An alert can lag the failure by
one minute.
