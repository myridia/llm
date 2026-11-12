#!/bin/bash

# id: 4
# group: MODELS
# desc: Install active model

TASK_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TASK_DIR/.." && pwd)
. "$ROOT/ask.d/lib.sh"

pull_model
