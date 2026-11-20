#!/bin/bash

# id: 2
# group: SERVER
# desc: Status (server, model, models, CPU/GPU)

TASK_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TASK_DIR/.." && pwd)
. "$ROOT/ask.d/lib.sh"

status_server
