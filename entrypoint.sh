#!/usr/bin/env bash
set -e

ISCE_HOME="$(python3 - <<'PY'
import os, isce
print(os.path.dirname(isce.__file__))
PY
)"

export ISCE_HOME
export ISCE_SRC=/opt/isce2-src
export ISCE_STACK_ROOT=/opt/isce2-src/contrib/stack
export ISCE_STACK_BIN=/opt/isce2-src/contrib/stack/topsStack

export PATH="${ISCE_STACK_BIN}:${ISCE_HOME}/applications:${PATH}"
export PYTHONPATH="${ISCE_STACK_ROOT}:${ISCE_HOME}:${PYTHONPATH:-}"

exec "$@"