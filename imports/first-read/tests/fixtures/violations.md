# Upgrade the broker

The migration has been applied by the operator; it can't be rolled back. You
should verify the config file prior to running the script, in order to ensure
that the behaviour is correct.

WARNING: CARE IS REQUIRED HERE.

When running the migration, the consumer is failing because the offset is
committed by the worker before it writes the record, which means that a crash
between those two operations will advance the offset and lose the record
permanently, and this is a significant problem.

Note: Make sure the flag is off before you deploy.

1. Set up the replica and turn on the flag, then restart it.
2. If the reviewer approves, he merges the branch.

Refer to `docs/foo.md` (e.g. the section on retries) and the "DO NOT TOUCH"
placard. The API MUST return 429. See https://example.com/a;b for details.
