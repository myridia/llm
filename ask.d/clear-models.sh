#!/bin/bash

# id: 18
# group: MODELS
# desc: Delete ALL models (typed YES)

TASK_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TASK_DIR/.." && pwd)
. "$ROOT/ask.d/lib.sh"

clear_models
