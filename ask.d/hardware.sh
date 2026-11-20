#!/bin/bash

# id: 9
# group: SYSTEM
# desc: Hardware analysis (OS/CPU/RAM/GPU)

TASK_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TASK_DIR/.." && pwd)
. "$ROOT/ask.d/lib.sh"

hardware_info
