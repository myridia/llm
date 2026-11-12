#!/bin/bash

# id: 12
# group: OPENCODE
# desc: Install global opencode setup

TASK_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TASK_DIR/.." && pwd)
. "$ROOT/ask.d/lib.sh"

install_opencode_rules
