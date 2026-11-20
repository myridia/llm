#!/bin/bash

# id: 15
# group: OPENCODE
# desc: Install oc launcher (~/.local/bin/oc)

TASK_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TASK_DIR/.." && pwd)
. "$ROOT/ask.d/lib.sh"

install_launcher
