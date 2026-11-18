# Service start

The service reads the config file from the volume when it starts, and
then it examines each schema in the registry for a new version. After the
service examines the schemas, it starts the listener on the port that the
config file names, so that clients can connect to it. If one schema is not
valid, the service writes an error to the log and then stops, because a bad
schema corrupts the index.
