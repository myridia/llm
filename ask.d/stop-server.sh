#!/bin/bash

# id: 3
# group: SERVER
# desc: Stop server

TASK_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TASK_DIR/.." && pwd)
. "$ROOT/ask.d/lib.sh"

stop_server
