#!/bin/bash

# id: 16
# group: MODELS
# desc: Context-size report (built-in vs num_ctx)

TASK_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TASK_DIR/.." && pwd)
. "$ROOT/ask.d/lib.sh"

show_context
