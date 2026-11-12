#!/bin/bash

# id: 7
# group: CHAT
# desc: Chat (interactive)

TASK_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TASK_DIR/.." && pwd)
. "$ROOT/ask.d/lib.sh"

interactive_chat
