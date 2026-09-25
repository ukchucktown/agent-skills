#!/bin/sh
set -eu
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec node "$script_directory/project-workflow.cjs" resolve "$@" --start-settings
