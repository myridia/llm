#!/bin/bash

# id: 8
# group: OPENCODE
# desc: Launch opencode (kitty if present)

TASK_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TASK_DIR/.." && pwd)
. "$ROOT/ask.d/lib.sh"

run_opencode
