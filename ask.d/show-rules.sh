#!/bin/bash

# id: 14
# group: OPENCODE
# desc: Show rules in effect (what a project loads)

TASK_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TASK_DIR/.." && pwd)
. "$ROOT/ask.d/lib.sh"

show_rules
