# Index status

The index is stale. Queries return old rows. The worker did not run. The team
found the cause.

The service reads the config file from the mounted volume at start. The service
examines each schema in the registry for a newer version. The service starts
the listener on the port that the config file names.

1. Stop the consumer.
2. Drain the queue.
3. Start the consumer.
