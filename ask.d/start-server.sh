#!/bin/bash

# id: 1
# group: SERVER
# desc: Start Ollama server

TASK_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TASK_DIR/.." && pwd)
. "$ROOT/ask.d/lib.sh"

start_server
