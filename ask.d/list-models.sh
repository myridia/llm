#!/bin/bash

# id: 17
# group: MODELS
# desc: List all installed models (sizes + store)

TASK_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TASK_DIR/.." && pwd)
. "$ROOT/ask.d/lib.sh"

list_models
