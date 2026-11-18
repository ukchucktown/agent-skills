# Index status

The index is stale because the worker did not run, so queries return old rows.
The team found the cause on Monday.

The service reads the config file from the mounted volume at start and examines
each schema in the registry for a newer version. Then it starts the listener on
the port that the config file names.

1. Stop the consumer.
2. Drain the queue.
3. Start the consumer.
