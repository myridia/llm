#!/bin/bash

# id: 21
# group: MODELS
# desc: Use qwen3:14b-64k (the working agent)

TASK_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TASK_DIR/.." && pwd)
. "$ROOT/ask.d/lib.sh"

use_model "qwen3:14b-64k" "the working agent, reliable tool calls"
