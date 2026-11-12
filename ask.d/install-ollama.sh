#!/bin/bash

# id: 6
# group: SERVER
# desc: Install Ollama (only if not found)

TASK_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TASK_DIR/.." && pwd)
. "$ROOT/ask.d/lib.sh"

install_ollama
