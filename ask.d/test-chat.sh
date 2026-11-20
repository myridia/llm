#!/bin/bash

# id: 5
# group: CHAT
# desc: Test chat

TASK_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TASK_DIR/.." && pwd)
. "$ROOT/ask.d/lib.sh"

test_chat
