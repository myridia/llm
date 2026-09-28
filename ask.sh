#!/bin/bash
# hello_llm_translate local LLM menu (Ollama — switchable Qwen3 / Qwen3-Coder models, CPU)
# Port 11434, OpenAI-compatible API for opencode.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OLLAMA_BIN="${OLLAMA_BIN:-}"
if [ -z "$OLLAMA_BIN" ]; then
  for c in "$(command -v ollama)" /usr/local/bin/ollama /usr/bin/ollama /home/veto/.local/bin/ollama; do
    [ -n "$c" ] && [ -x "$c" ] && OLLAMA_BIN="$c" && break
  done
fi
NEED_INSTALL=0
if [ -z "$OLLAMA_BIN" ]; then
  NEED_INSTALL=1
  echo "Warning: ollama binary not found (checked PATH, /usr/local/bin, /usr/bin, ~/.local/bin)."
  echo "Use task 6 to install it, or set OLLAMA_BIN to an existing binary."
fi
MODEL="${MODEL:-}"
MODEL_DEFAULT="qwen3:14b"
BIND="${OLLAMA_HOST:-0.0.0.0:11434}"
HOST="${HOST:-127.0.0.1:11434}"
PORT="${PORT:-11434}"
PID_FILE="$DIR/.ollama.pid"
LOG_FILE="$DIR/.ollama.log"
MODEL_FILE="$DIR/.model"
[ -z "$MODEL" ] && MODEL="$(cat "$MODEL_FILE" 2>/dev/null)"
MODEL="${MODEL:-$MODEL_DEFAULT}"

systemd_managed() {
  command -v systemctl >/dev/null 2>&1 && systemctl is-active ollama >/dev/null 2>&1
}

install_ollama() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://ollama.com/install.sh | sh
    OLLAMA_BIN="$(command -v ollama)"
    if [ -n "$OLLAMA_BIN" ]; then
      NEED_INSTALL=0
      echo "Ollama installed: $OLLAMA_BIN"
    else
      echo "Install finished but ollama not found — add /usr/local/bin to PATH or set OLLAMA_BIN."
    fi
  else
    echo "curl not found — install Ollama manually: https://ollama.com/download"
  fi
}

server_up() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    return 0
  fi
  curl -s --max-time 2 "http://$HOST/api/tags" >/dev/null 2>&1
}

start_server() {
  if systemd_managed; then
    echo "Ollama is a systemd service (ollama.service) — using systemctl"
    systemctl start ollama
    echo "Started."
    return 0
  fi
  if server_up; then
    echo "Ollama already running on $HOST"
    return 0
  fi
  echo "Starting Ollama (listen $BIND, log: $LOG_FILE)"
  nohup env OLLAMA_HOST="$BIND" "$OLLAMA_BIN" serve >"$LOG_FILE" 2>&1 &
  echo $! >"$PID_FILE"
  for i in $(seq 1 30); do
    sleep 1
    if server_up; then
      echo "Ready."
      return 0
    fi
  done
  echo "Failed to start; see $LOG_FILE"
  return 1
}

stop_server() {
  if systemd_managed; then
    echo "Ollama is a systemd service (ollama.service) — using systemctl"
    systemctl stop ollama
    echo "Stopped."
    return 0
  fi
  if [ -f "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null
    rm -f "$PID_FILE"
    echo "Stopped."
  else
    pkill -f "ollama serve" 2>/dev/null && echo "Stopped." || echo "Not running."
  fi
}

status_server() {
  if systemd_managed; then
    echo "Running via systemd (ollama.service) — models:"
    curl -s "http://$HOST/api/tags" | python3 -c "import json,sys; [print('  -', m['name'], f\"{m['size']/1e9:.1f} GB\") for m in json.load(sys.stdin).get('models',[])]" 2>/dev/null || echo "  (none)"
    return 0
  fi
  if server_up; then
    echo "Running on $HOST — models:"
    curl -s "http://$HOST/api/tags" | python3 -c "import json,sys; [print('  -', m['name'], f\"{m['size']/1e9:.1f} GB\") for m in json.load(sys.stdin).get('models',[])]" 2>/dev/null || echo "  (none)"
  else
    echo "Not running."
  fi
}

hardware_info() {
  echo "== OS =="
  [ -f /etc/os-release ] && grep -E "^PRETTY_NAME=" /etc/os-release | cut -d= -f2 | tr -d '"'
  echo "Kernel: $(uname -r)  ($(uname -m))"

  echo ""
  echo "== CPU =="
  grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//' || echo "(unknown)"
  echo "Cores/threads: $(nproc --all 2>/dev/null || nproc)"
  FLAGS=$(grep -m1 flags /proc/cpuinfo)
  for f in avx512f avx512bw avx2 avx vpclmulqdq sse4_2; do
    echo "$FLAGS" | grep -q "\b$f\b" && echo "  $f: yes" || echo "  $f: no"
  done

  echo ""
  echo "== Memory (RAM / swap) =="
  free -h 2>/dev/null || grep -E "MemTotal|MemAvailable" /proc/meminfo

  echo ""
  echo "== Disk =="
  df -h "$HOME" 2>/dev/null | tail -1
  df -h "$HOME/.ollama" 2>/dev/null | tail -1 || echo "  ~/.ollama not present yet (pull a model first)"

  echo ""
  echo "== GPU =="
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null || nvidia-smi
  else
    echo "  no nvidia-smi"
    ls /dev/nvidia* >/dev/null 2>&1 && echo "  nvidia device nodes present (driver module loaded?)"
  fi
  if command -v lspci >/dev/null 2>&1; then
    lspci 2>/dev/null | grep -i -E "vga|3d|display" | sed 's/^/  /'
  fi

  echo ""
  echo "== Ollama =="
  if server_up; then
    curl -s "http://$HOST/api/tags" | python3 -c "import json,sys; m=json.load(sys.stdin).get('models',[]); [print('  -', x['name'], f\"{x['size']/1e9:.1f} GB\") for x in m] or print('  (no models pulled)')" 2>/dev/null || echo "  (could not list)"
  else
    echo "  not running"
  fi

  echo ""
  echo "== Rough CPU-inference guide (RAM/cores) =="
  local mem_kb
  mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  if [ "${mem_kb:-0}" -ge 48000000 ]; then
    echo "  RAM >= 48 GB  -> 14-32B dense as opencode agent; qwen3.6:35b-a3b / qwen3-coder:30b fit but are CodeAct (unreliable in opencode)"
  elif [ "${mem_kb:-0}" -ge 24000000 ]; then
    echo "  RAM >= 24 GB  -> qwen3:14b comfortable"
  else
    echo "  RAM < 24 GB   -> qwen3:8b-ish"
  fi
}

select_model() {
  local presets=(
    "qwen3:14b|dense 14B, thinking — reliable opencode tool calls (~9 GB, recommended)"
    "qwen3.6:35b-a3b|CodeAct dialect — unreliable for opencode (emits <tool_code>), fine for chat (~30 GB)"
    "qwen3-coder:30b|CodeAct/execute — unreliable for opencode, fast bulk code (~19 GB)"
    "qwen3:32b|dense 32B, thinking (~19 GB)"
    "qwen3:8b|smallest (~4.7 GB)"
  )
  SELECTED=""
  echo "Current model: $MODEL"
  echo "Presets:"
  local i
  for i in "${!presets[@]}"; do
    printf "  %d) %-18s %s\n" "$((i+1))" "${presets[$i]%|*}" "${presets[$i]#*|}"
  done
  read -rp "Pick a preset number, or type any model name (empty to cancel): " choice
  [ -z "$choice" ] && { echo "Cancelled."; return 1; }
  if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "${#presets[@]}" ] 2>/dev/null; then
    SELECTED="${presets[$((choice-1))]%|*}"
  else
    SELECTED="$choice"
  fi
}

switch_model() {
  select_model || return
  if [ "$SELECTED" = "$MODEL" ]; then
    echo "Already using $MODEL."
    return
  fi
  echo "$SELECTED" > "$MODEL_FILE"
  MODEL="$SELECTED"
  echo "Switched to $MODEL (saved in .model). Pull it with task 4 or 11 if not present yet:"
  "$OLLAMA_BIN" list 2>/dev/null || echo "  (ollama not available)"
}

download_model() {
  select_model || return
  if [ "$SELECTED" = "$MODEL" ]; then
    echo "Pulling active model: $SELECTED"
  else
    echo "Pulling: $SELECTED"
  fi
  "$OLLAMA_BIN" pull "$SELECTED"
  if [ $? -eq 0 ] && [ "$SELECTED" != "$MODEL" ]; then
    read -rp "Make $SELECTED the active model too? [y/N] " ans
    case "$ans" in
      y|Y|yes)
        echo "$SELECTED" > "$MODEL_FILE"
        MODEL="$SELECTED"
        echo "Switched active model to $MODEL."
        ;;
      *) echo "OK — switch later with task 10." ;;
    esac
  fi
}

install_opencode_rules() {
  local conf_dir="$HOME/.config/opencode"
  local rules="$conf_dir/local-model-rules.md"
  mkdir -p "$conf_dir" || { echo "Failed to create $conf_dir"; return 1; }
  cp "$DIR/.opencode/local-model-rules.md" "$rules" || { echo "Source rules file missing."; return 1; }
  python3 - "$conf_dir" "$rules" "$DIR/opencode.json" <<'PYEOF'
import json, os, re, sys
conf_dir, rules, src = sys.argv[1], sys.argv[2], sys.argv[3]
jsonf, jsoncf = os.path.join(conf_dir, "opencode.json"), os.path.join(conf_dir, "opencode.jsonc")
conf = jsonf if os.path.exists(jsonf) else (jsoncf if os.path.exists(jsoncf) else jsonf)
data = {}
if os.path.exists(conf):
    try:
        with open(conf) as f:
            data = json.load(f)
    except Exception:
        print("WARNING: existing %s is not valid JSON — left untouched." % conf)
        print('Manual step: add "instructions": ["%s"] to your global opencode config.' % rules)
        sys.exit(0)
instr = data.setdefault("instructions", [])
if rules not in instr:
    instr.append(rules)
srcd = {}
if os.path.exists(src):
    try:
        with open(src) as f:
            srcd = json.load(f)
    except Exception:
        print("WARNING: source %s is not valid JSON — provider/model merge skipped." % src)
else:
    print("NOTE: %s not found — provider/model merge skipped." % src)
prov = srcd.get("provider", {})
merged = []
if prov:
    tgt = data.setdefault("provider", {})
    for name, pdef in prov.items():
        tgt[name] = pdef
        merged.append(name)
if srcd.get("model"):
    data["model"] = srcd["model"]
data.setdefault("$schema", "https://opencode.ai/config.json")
with open(conf, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("%s -> instructions now: %s" % (conf, instr))
if merged:
    print("provider merged: %s (models: %s)" % (", ".join(merged), ", ".join(sorted(prov[merged[0]].get("models", {})))))
if srcd.get("model"):
    print("default model: %s" % data["model"])
block = """<!-- BEGIN hello_llm_translate -->
## Local model ground rules (auto-generated by ask.sh task 12)
- You run INSIDE a real project directory and have full file and shell access through your tools.
- Never claim you have no working directory, that you are a virtual assistant or "an AI without
  access to your system", that you cannot read files, or that you cannot run shell commands.
- If asked which folder/directory you are in, call the bash tool with `pwd` and report its exact output.
- Use tools by exact name only: bash, glob, grep, read, edit, write, task, todowrite, webfetch, skill.
  There is NO `list`, `explore`, or `execute` tool.
- When asked to list or show "this folder", call bash with `ls` (or glob with a pattern): the working
  directory is the folder meant.
- Act, then explain in 1-2 lines. Do not ask clarifying questions when an action is possible.
- If the answer is already in your context (which project, which folder, which rules, which model,
  what you can do), answer directly in text. Never launch the explore/general subagent, and never
  call a tool, just to answer a question about the session itself.
<!-- END hello_llm_translate -->"""
agents = os.path.join(conf_dir, "AGENTS.md")
cur = ""
if os.path.exists(agents):
    try:
        with open(agents) as f:
            cur = f.read()
    except Exception:
        cur = ""
if "<!-- BEGIN hello_llm_translate -->" in cur:
    new = re.sub(r"<!-- BEGIN hello_llm_translate -->.*?<!-- END hello_llm_translate -->", block, cur, flags=re.S)
elif cur.strip():
    new = cur.rstrip() + "\n\n" + block + "\n"
else:
    new = block + "\n"
with open(agents, "w") as f:
    f.write(new)
print("global AGENTS.md (auto-loaded in every session): %s" % agents)
PYEOF
  local cmd_dir="$conf_dir/commands"
  local plug_dir="$conf_dir/plugins"
  if [ -f "$DIR/.opencode/plugins/session-env.js" ]; then
    if mkdir -p "$plug_dir" && cp "$DIR/.opencode/plugins/session-env.js" "$plug_dir/session-env.js"; then
      echo "Installed plugin: $plug_dir/session-env.js (injects working directory + tool facts into the system prompt)"
    else
      echo "WARNING: could not install $plug_dir/session-env.js"
    fi
  fi
  if mkdir -p "$cmd_dir" && cat > "$cmd_dir/rules.md" <<CMDEOF
---
description: Show which rules, AGENTS.md and models opencode loaded for this project
---
Resolved configuration for this project (resolved by $DIR/ask.sh, task 14):

!\`$DIR/ask.sh --rules\`

Now report that list to the user verbatim: every path with its [ok] / [MISSING] / [none] marker and line count, the provider and its models, and the default model. Do not call any tool, do not launch a subagent, and do not add anything that is not in the list.
CMDEOF
  then
    echo "Installed /rules command: $cmd_dir/rules.md"
  else
    echo "WARNING: could not write $cmd_dir/rules.md"
  fi
  echo "Global opencode setup installed:"
  echo "  $rules"
  echo "  (opencode.json[c] in that dir registers the rules, the ollama provider + models, and the default model)"
}

fix_num_ctx() {
  # Ensure every pulled model has at least nctx running context. Ollama's default
  # window can be small (e.g. 4096 on some models) and opencode pushes its tool
  # definitions at the END of the prompt — a too-small window truncates them and
  # the model "forgets" it has tools like `bash`. Only raises; models already at
  # or above the floor (e.g. qwen3:14b ships with 40960) are skipped.
  local nctx="${NUM_CTX:-32768}"
  if ! server_up; then
    echo "Server not running — start it with task 1 first."
    return 1
  fi
  echo "Raising any model below num_ctx=$nctx (NUM_CTX env overrides)."
  local name cur fails=0 list_out
  list_out="$("$OLLAMA_BIN" list --format json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); lst=d if isinstance(d,list) else d.get('models',[]); [print(m.get('name','')) for m in lst]" 2>/dev/null)" || list_out="$("$OLLAMA_BIN" list 2>/dev/null | tail -n +2 | awk '{print $1}')"
  [ -z "$list_out" ] && { echo "No models found via 'ollama list'."; return 1; }
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    echo "== $name =="
    cur="$("$OLLAMA_BIN" show "$name" 2>/dev/null | grep -oE 'context length[[:space:]]+[0-9]+' | grep -oE '[0-9]+')"
    if [ -n "$cur" ] && [ "$cur" -ge "$nctx" ]; then
      echo "  ok — already $cur (>= $nctx), skipping"
      continue
    fi
    echo "  raising $([ -n "$cur" ] && echo "$cur -> ")$nctx..."
    if printf '/set parameter num_ctx %s\n/save %s\n/bye\n' "$nctx" "$name" \
        | "$OLLAMA_BIN" run "$name" 2>&1 | tail -6; then
      :
    else
      fails=$((fails+1))
    fi
  done <<< "$list_out"
  echo ""
  echo "Done (failures: $fails). Verify: ollama show <model> | grep -i context"
}

opencode_bin() {
  local c
  for c in "$(command -v opencode)" /root/.opencode/bin/opencode "$HOME/.opencode/bin/opencode" /usr/local/bin/opencode /usr/bin/opencode; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

show_rules() {
  local dir="${1:-$PWD}" root
  dir="$(cd "$dir" 2>/dev/null && pwd)" || { echo "No such directory: $dir"; return 1; }
  root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"
  [ -z "$root" ] && root="$dir"
  python3 - "$dir" "$root" "$HOME/.config/opencode" <<'PYEOF'
import json, os, sys
cwd, root, confdir = sys.argv[1], sys.argv[2], sys.argv[3]

def rel(p):
    return p.replace(os.path.expanduser("~"), "~")

def load(p):
    try:
        with open(p) as f:
            return json.load(f)
    except Exception:
        return None

def show(path, base, origin):
    p = path
    if not os.path.isabs(p):
        p = os.path.join(path if path.startswith("~") else base, path.lstrip("~/") if path.startswith("~") else path)
    p = os.path.expanduser(p)
    if os.path.exists(p):
        n = sum(1 for _ in open(p, errors="ignore"))
        print("    [ok]      %-52s %4s lines  (%s)" % (rel(p), n, origin))
    else:
        print("    [MISSING] %-52s (%s)" % (rel(p), origin))

print("== Rules in effect ==")
print("cwd:         %s" % cwd)
print("project root: %s%s" % (root, "" if root != "/" else "   <-- no .git found: opencode falls back to the '/' global project"))
print("")

print("Global config (%s):" % rel(confdir))
gconf = None
gpath = None
for name in ("opencode.json", "opencode.jsonc"):
    p = os.path.join(confdir, name)
    if os.path.exists(p):
        gpath, gconf = p, load(p)
        break
if gpath:
    print("  %s%s" % (rel(gpath), "" if gconf else "   (invalid JSON)"))
    if gconf:
        for i in gconf.get("instructions") or []:
            show(i, confdir, "global instructions")
        for name, pdef in (gconf.get("provider") or {}).items():
            print("    provider: %s -> %s" % (name, ", ".join(sorted((pdef.get("models") or {})))))
        if gconf.get("model"):
            print("    default model: %s" % gconf["model"])
else:
    print("  (none — run task 12 to install)")
show(os.path.join(confdir, "AGENTS.md"), confdir, "global AGENTS.md (auto-loaded)")
for plugdir in (os.path.join(confdir, "plugins"), os.path.join(cwd, ".opencode", "plugins")):
    if os.path.isdir(plugdir):
        for f in sorted(os.listdir(plugdir)):
            if f.endswith((".js", ".ts", ".mjs")):
                print("    [plugin]  %s" % rel(os.path.join(plugdir, f)))
print("")

chain = []
d = cwd
while True:
    chain.append(d)
    if d == root or d == "/":
        break
    d = os.path.dirname(d)

print("Project config (cwd -> project root):")
found = False
for d in chain:
    for name in ("opencode.json", "opencode.jsonc"):
        p = os.path.join(d, name)
        if os.path.exists(p):
            found = True
            data = load(p) or {}
            print("  %s%s" % (rel(p), "" if data else "   (invalid JSON)"))
            for i in data.get("instructions") or []:
                show(i, d, "project instructions")
            for name2, pdef in (data.get("provider") or {}).items():
                print("    provider: %s -> %s" % (name2, ", ".join(sorted((pdef.get("models") or {})))))
            if data.get("model"):
                print("    default model: %s" % data["model"])
if not found:
    print("  (none — global config only)")
print("")

print("AGENTS.md chain (project root -> cwd):")
for d in reversed(chain):
    p = os.path.join(d, "AGENTS.md")
    if os.path.exists(p):
        n = sum(1 for _ in open(p, errors="ignore"))
        print("    [ok]      %-52s %4s lines" % (rel(p), n))
    else:
        print("    [none]    %s" % rel(p))
PYEOF
}

install_launcher() {
  local bindir="${BINDIR:-$HOME/.local/bin}" bin
  bin="$(command -v opencode)" || { echo "opencode not found in PATH — cannot write the launcher."; return 1; }
  mkdir -p "$bindir" || { echo "Failed to create $bindir"; return 1; }
  cat > "$bindir/oc" <<LAUNCHER
#!/usr/bin/env bash
# oc — opencode launcher (generated by $DIR/ask.sh task 15)
# Prints the rules opencode will load for this directory, then starts opencode here.
"$DIR/ask.sh" --rules
echo ""
echo "Starting opencode in \$PWD — pass a model to override: oc --model ollama/qwen3:14b"
exec "$bin" "\$@"
LAUNCHER
  chmod +x "$bindir/oc" || return 1
  echo "Installed: $bindir/oc"
  case ":$PATH:" in
    *":$bindir:"*) ;;
    *) echo "Note: $bindir is not in PATH. Add to ~/.bashrc:"; echo "  export PATH=\"\$PATH:$bindir\"" ;;
  esac
  echo "Usage: cd <project> && oc   |   oc --model ollama/qwen3:14b"
}

run_opencode() {
  local bin proj root ans
  bin="$(opencode_bin)" || { echo "opencode not found — install it (https://opencode.ai) or set OPENCODE_BIN."; return 1; }
  server_up || start_server || { echo "Ollama is not running — aborted."; return 1; }
  local proj_prompt="${PROJECT:-$PWD}"
  if [ -z "${PROJECT:-}" ]; then
    read -rp "Project directory [default: $PWD]: " proj_prompt
    [ -z "$proj_prompt" ] && proj_prompt="$PWD"
  fi
  proj="$(cd "$proj_prompt" 2>/dev/null && pwd)" || { echo "No such directory: $proj_prompt"; return 1; }
  root="$(git -C "$proj" rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "$root" ]; then
    echo "No .git in $proj or any parent — opencode would fall back to the '/' global project."
    read -rp "Run 'git init' in $proj? (also required for /undo and /redo) [y/N] " ans
    case "$ans" in
      y|Y|yes) git -C "$proj" init --quiet && echo "Initialized git repo." ;;
      *) echo "Continuing without git — opencode will likely not treat it as a project." ;;
    esac
  fi
  echo ""
  show_rules "$proj"
  echo ""
  echo "Starting opencode in $proj with local model ($MODEL)"
  cd "$proj" || return 1
  exec "$bin" --model "ollama/$MODEL" "$proj"
}

pull_model() {
  "$OLLAMA_BIN" pull "$MODEL"
}

test_chat() {
  curl -s "http://$HOST/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Translate 'Hello' to Thai in one word.\"}],\"max_tokens\":512}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'])"
}

interactive_chat() {
  if ! server_up; then
    echo "Server not running — start it with task 1 first."
    return 1
  fi
  echo "Interactive chat with $MODEL (empty line or /quit to exit, /clear to reset, /models to list)."
  local history="[]"
  local tmpf
  tmpf="$(mktemp)"
  while true; do
    printf "\n> "
    if ! IFS= read -r line; then
      break
    fi
    case "$line" in
      "") break ;;
      "/quit") break ;;
      "/clear") history="[]"; echo "(history cleared)"; continue ;;
      "/models") "$OLLAMA_BIN" list 2>/dev/null; continue ;;
      *) ;;
    esac
    history="$(python3 - "$history" "$line" <<'PYEOF'
import json,sys
hist=json.loads(sys.argv[1])
hist.append({"role":"user","content":sys.argv[2]})
print(json.dumps(hist))
PYEOF
)"
    payload="$(python3 - "$history" "$MODEL" <<'PYEOF'
import json,sys
hist=json.loads(sys.argv[1])
print(json.dumps({"model":sys.argv[2],"messages":hist,"stream":True,"max_tokens":1024}))
PYEOF
)"
    echo ""
    curl -sN "http://$HOST/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -d "$payload" \
      | python3 -c "
import json,sys
reply=''
for line in sys.stdin:
    line=line.strip()
    if not line.startswith('data:'):
        continue
    data=line[5:].strip()
    if data=='[DONE]':
        break
    try:
        chunk=json.loads(data)
    except Exception:
        continue
    c=chunk.get('choices',[{}])[0].get('delta',{}).get('content') or ''
    if c:
        sys.stdout.write(c); sys.stdout.flush(); reply+=c
import os
with open(os.environ['TMPF'],'w') as f:
    f.write(reply)
" 2>/dev/null
    TMPF="$tmpf"
    history="$(python3 - "$history" "$tmpf" <<'PYEOF'
import json,sys
hist=json.loads(sys.argv[1])
try:
    with open(sys.argv[2]) as f:
        reply=f.read()
    hist.append({"role":"assistant","content":reply})
except Exception:
    pass
print(json.dumps(hist))
PYEOF
)"
  done
  rm -f "$tmpf"
  echo ""
}

case "${1:-}" in
  --rules) show_rules "${2:-$PWD}"; exit 0 ;;
  --help|-h)
    echo "usage: $0 [--rules [dir]]   (no args = interactive menu)"
    exit 0 ;;
esac

while true; do
  echo ""
echo "hello_llm_translate — local LLM ($MODEL)"
[ "$NEED_INSTALL" = "1" ] && echo "  !  Ollama not installed yet — run task 6"
echo "  1  Start Ollama server"
echo "  2  Status"
echo "  3  Stop server"
echo "  4  Pull model $MODEL"
echo "  5  Test chat"
echo "  6  Install Ollama (only if not found)"
echo "  7  Chat (interactive)"
echo "  8  OpenCode (agent, local model)"
echo "  9  Hardware analysis (OS/CPU/RAM/GPU)"
echo "  10 Switch local model (presets + raw name, saved in .model)"
echo "  11 Download a model (pick preset or type any name, then optionally activate it)"
echo "  12 Install global opencode setup (rules + ollama provider/models + default model in ~/.config/opencode)"
echo "  13 Fix Ollama context (num_ctx) for all models (prevents tool-def truncation; NUM_CTX override)"
echo "  14 Show rules in effect (which instructions/AGENTS.md/models a project loads; no launch)"
echo "  15 Install 'oc' launcher (~/.local/bin/oc: prints rules, then starts opencode in cwd)"
echo "  0  Exit"
  if ! read -rp "Task: " task; then
    break
  fi
  case "$task" in
    1) start_server ;;
    2) status_server ;;
    3) stop_server ;;
    4) pull_model ;;
    5) test_chat ;;
    6) install_ollama ;;
    7) interactive_chat ;;
    8) run_opencode ;;
    9) hardware_info ;;
    10) switch_model ;;
    11) download_model ;;
    12) install_opencode_rules ;;
    13) fix_num_ctx ;;
    14) show_rules ;;
    15) install_launcher ;;
    0) break ;;
    *) echo "Unknown task" ;;
  esac
done
exit 0