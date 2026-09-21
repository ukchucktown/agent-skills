#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GH_ISSUE_COMMAND=cancel.sh exec "$script_directory/clean.sh" --cancel "$@"
