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
KITTY_BIN="${KITTY_BIN:-kitty}"
case "$KITTY_BIN" in
  0|none) KITTY_BIN="" ;;
  */*) [ -x "$KITTY_BIN" ] || KITTY_BIN="" ;;
  *) KITTY_BIN="$(command -v "$KITTY_BIN" 2>/dev/null)" ;;
esac
MODEL="${MODEL:-}"
MODEL_DEFAULT="qwen3:14b-64k"
BIND="${OLLAMA_HOST:-0.0.0.0:11434}"
HOST="${HOST:-127.0.0.1:11434}"
PORT="${PORT:-11434}"
CTX_FLOOR="${CTX_FLOOR:-65536}"
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

model_names() {
  model_table | cut -f1
}

model_table() {
  curl -s --max-time 5 "http://$HOST/api/tags" 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
for m in d.get("models", []):
    print("%s\t%.1f" % (m.get("name", ""), m.get("size", 0) / 1e9))
'
}

model_installed() {
  model_names | grep -qF -- "$1"
}

model_builtin_ctx() {
  "$OLLAMA_BIN" show "$1" 2>/dev/null | grep -ioE 'context length[[:space:]]+[0-9]+' | grep -oE '[0-9]+' | head -1
}

model_num_ctx() {
  "$OLLAMA_BIN" show --parameters "$1" 2>/dev/null | grep -ioE 'num_ctx[[:space:]:]+[0-9]+' | grep -oE '[0-9]+' | head -1
}

# A "<base>-<N>k" tag (e.g. qwen3:14b-64k) is a local variant of <base> with
# num_ctx baked in via Modelfile + ollama create. The ollama REPL
# (/set parameter num_ctx + /save) is unreliable on some builds — it feeds the
# slash lines to the model as chat — so variants are built deterministically.
model_ensure() {
  local tag="$1" base nctx mf
  model_installed "$tag" && return 0
  if [[ "$tag" =~ ^(.+)-([0-9]+)k$ ]]; then
    base="${BASH_REMATCH[1]}"
    nctx=$(( ${BASH_REMATCH[2]} * 1024 ))
    if ! model_installed "$base"; then
      echo "Pulling base $base (needed to build $tag)..."
      "$OLLAMA_BIN" pull "$base" || { echo "Pull failed — $tag needs it."; return 1; }
    fi
    echo "Building $tag (PARAMETER num_ctx $nctx, from $base)..."
    mf="$(mktemp)"
    "$OLLAMA_BIN" show --modelfile "$base" > "$mf" 2>/dev/null || { rm -f "$mf"; echo "Failed to read Modelfile for $base."; return 1; }
    sed -i -e '/num_ctx[[:space:]]/d' "$mf"
    printf 'PARAMETER num_ctx %s\n' "$nctx" >> "$mf"
    if "$OLLAMA_BIN" create "$tag" -f "$mf" >/dev/null 2>&1; then
      rm -f "$mf"
      echo "Done: $tag carries num_ctx $nctx."
      return 0
    fi
    rm -f "$mf"
    echo "Failed to create $tag."
    return 1
  fi
  "$OLLAMA_BIN" pull "$tag"
}

parse_ps() {
  "$OLLAMA_BIN" ps 2>/dev/null | tail -n +2 | awk 'NF {
    s = 0; e = 0
    for (i = 1; i <= NF; i++) {
      if (s == 0 && $i ~ /%/) s = i
      if (index($i, "CPU") || index($i, "GPU")) e = i
    }
    p = ""
    if (s > 0 && e >= s) for (i = s; i <= e; i++) p = (p == "" ? $i : p " " $i)
    printf "    %-22s %s\n", $1, (p == "" ? "processor not reported (older ollama)" : p)
  }'
}

processor_info() {
  local rows ans pid i
  rows="$(parse_ps)"
  if [ -n "$rows" ]; then
    printf '%s\n' "$rows"
    return 0
  fi
  echo "    no model loaded — CPU/GPU split is only visible for a resident model"
  read -rp "    Load $MODEL briefly (~30s) to detect it? [y/N] " ans
  case "$ans" in
    [Yy]*) ;;
    *) echo "    skipped. Detect manually: ollama run $MODEL hi >/dev/null 2>&1 & sleep 8; ollama ps"; return 0 ;;
  esac
  "$OLLAMA_BIN" run "$MODEL" "count from 1 to 50" >/dev/null 2>&1 &
  pid=$!
  for i in $(seq 1 15); do
    sleep 2
    [ -n "$(parse_ps)" ] && break
  done
  wait "$pid" 2>/dev/null
  rows="$(parse_ps)"
  if [ -n "$rows" ]; then
    printf '%s\n' "$rows"
  else
    echo "    still nothing resident — the run may have failed; try task 5 and look for errors"
  fi
}

opencode_default_model() {
  python3 - "$DIR/opencode.json" "$DIR/opencode.jsonc" <<'PYEOF' 2>/dev/null
import json, re, sys
for path in sys.argv[1:]:
    try:
        raw = open(path).read()
    except OSError:
        continue
    try:
        cfg = json.loads(raw)
    except ValueError:
        raw = re.sub(r"//.*", "", raw)
        raw = re.sub(r",(\s*[}\]])", r"\1", raw)
        try:
            cfg = json.loads(raw)
        except ValueError:
            continue
    if cfg.get("model"):
        print(cfg["model"])
        break
PYEOF
}

status_server() {
  local how="manual (nohup)"
  systemd_managed && how="systemd service (ollama.service)"
  if systemd_managed || server_up; then
    echo "Ollama: running — $how"
    echo "  bind $BIND   probe $HOST"
  else
    echo "Ollama: NOT running — start it with task 1."
    return 1
  fi

  echo ""
  echo "  active model (task 10, saved in .model): $MODEL"
  model_installed "$MODEL" || echo "    ^ NOT INSTALLED — pull with task 4, or switch with task 10"

  local oc_model
  oc_model="$(opencode_default_model)"
  if [ -n "$oc_model" ]; then
    echo "  opencode default model: $oc_model"
    model_installed "${oc_model#*/}" \
      || echo "    ^ NOT INSTALLED — opencode cannot resolve it and silently falls back to its own default"
  fi

  echo ""
  echo "  models installed (context sizes: task 16):"
  model_table | while IFS=$'\t' read -r n s; do
    [ -z "$n" ] && continue
    printf '    %-22s %6s GB\n' "$n" "$s"
  done

  echo ""
  echo "  compute (CPU or GPU, per loaded model):"
  processor_info
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
    if ! model_table | while IFS=$'\t' read -r n s; do
      [ -z "$n" ] && continue
      printf '  - %-22s %6s GB\n' "$n" "$s"
    done; then
      echo "  (could not list)"
    fi
  else
    echo "  not running"
  fi

  echo ""
  echo "== Rough inference guide (VRAM decides GPU split, RAM decides what loads) =="
  local mem_kb vram_mb
  mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  vram_mb=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
  if [ -n "${vram_mb:-}" ]; then
    echo "  VRAM ${vram_mb} MB"
    if [ "$vram_mb" -ge 22000 ]; then
      echo "    -> 20 GB models (qwen3:32b) can load mostly on GPU"
    elif [ "$vram_mb" -ge 10000 ]; then
      echo "    -> 9 GB models (qwen3:14b) mostly on GPU; 20 GB models will split hard or fail"
    else
      echo "    -> under 10 GB: even qwen3:14b splits to CPU; qwen3:8b is the comfortable one"
    fi
  else
    echo "  VRAM unknown (no nvidia-smi) — if task 2 shows 100% CPU there is no usable NVIDIA GPU"
  fi
  if [ "${mem_kb:-0}" -ge 48000000 ]; then
    echo "  RAM >= 48 GB  -> any of the 3 registered models load, GPU or not"
  elif [ "${mem_kb:-0}" -ge 24000000 ]; then
    echo "  RAM >= 24 GB  -> qwen3:14b comfortable; qwen3:32b loads but offloads to CPU"
  else
    echo "  RAM < 24 GB   -> qwen3:8b-ish"
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

show_context() {
  if ! server_up; then
    echo "Server not running — start it with task 1 first."
    return 1
  fi
  echo "Context sizes. opencode needs >= $CTX_FLOOR: it appends tool definitions at the"
  echo "END of the prompt, so a smaller window truncates them and the model 'loses' its tools."
  echo ""
  printf '  %-22s %7s %10s %9s  %s\n' MODEL SIZE BUILT-IN NUM_CTX VERDICT
  local table n s b e eff verdict
  table="$(model_table)"
  if [ -z "$table" ]; then
    echo "  (no models pulled — task 4)"
    return 0
  fi
  while IFS=$'\t' read -r n s; do
    [ -z "$n" ] && continue
    b="$(model_builtin_ctx "$n")"
    e="$(model_num_ctx "$n")"
    eff="${e:-$b}"
    if [ -z "$b" ]; then
      verdict="unknown (ollama show failed)"
    elif [ "$eff" -lt "$CTX_FLOOR" ] 2>/dev/null; then
      verdict="TOO SMALL — reinstall via task 4 (bakes the -64k variant)"
    else
      verdict="ok"
    fi
    printf '  %-22s %6sG %10s %9s  %s\n' "$n" "$s" "${b:-?}" "${e:--}" "$verdict"
  done <<< "$table"
  echo ""
  echo "  BUILT-IN = model default, NUM_CTX = your saved override ('-' = none)."
  echo "  Effective window = NUM_CTX when set, else BUILT-IN. A -64k variant is the working agent."
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
  if ! model_installed "$MODEL"; then
    echo "Active model $MODEL is NOT installed — opencode cannot resolve it and will fall back to its own default."
    read -rp "Pull $MODEL now? [Y/n] " ans
    case "$ans" in
      [Nn]*|n|N|no) echo "Aborted."; return 1 ;;
      *) "$OLLAMA_BIN" pull "$MODEL" || { echo "Pull failed — aborted."; return 1; } ;;
    esac
  fi
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
  cd "$proj" || return 1
  if [ -n "$KITTY_BIN" ]; then
    echo "Starting opencode in $proj with local model ($MODEL) — opening a kitty window"
    "$KITTY_BIN" --single-instance --directory "$proj" "$bin" --model "ollama/$MODEL" "$proj"
    return $?
  fi
  echo "Starting opencode in $proj with local model ($MODEL)"
  exec "$bin" --model "ollama/$MODEL" "$proj"
}

use_model() {
  local tag="$1" label="$2" ans
  if ! server_up; then
    echo "Server not running — start it with task 1 first."
    return 1
  fi
  if [ "$tag" = "$MODEL" ] && model_installed "$tag"; then
    echo "Already active and installed: $tag"
  else
    echo "$tag" > "$MODEL_FILE"
    MODEL="$tag"
    echo "Active model -> $tag ($label), saved in .model"
  fi
  if ! model_installed "$tag"; then
    echo "Not installed."
    read -rp "Install $tag now? [Y/n] " ans
    case "$ans" in
      [Nn]*|n|N|no) echo "Aborted — opencode would fall back to its own default without it."; return 1 ;;
      *) model_ensure "$tag" || { echo "Install failed — aborted."; return 1; } ;;
    esac
  fi
  run_opencode
}

pull_model() {
  model_ensure "$MODEL"
}

list_models() {
  if ! server_up; then
    echo "Server not running — start it with task 1 first."
    return 1
  fi
  local table total
  table="$(model_table)"
  if [ -z "$table" ]; then
    echo "No models installed."
    return 0
  fi
  echo "Installed models (store: ${OLLAMA_MODELS:-$HOME/.ollama/models}):"
  printf '  %-24s %9s\n' NAME SIZE
  while IFS=$'\t' read -r n s; do
    [ -z "$n" ] && continue
    printf '  %-24s %7.1f GB\n' "$n" "$s"
  done <<< "$table"
  total="$(printf '%s\n' "$table" | awk -F'\t' '{s+=$2} END {printf "%.1f", s}')"
  echo "  TOTAL: $total GB"
  echo "  A -64k variant shares the base model's blobs; effective window per tag: task 16."
}

clear_models() {
  local names ans n fails=0
  if ! server_up; then
    echo "Server not running — start it with task 1 first."
    return 1
  fi
  names="$(model_names)"
  if [ -z "$names" ]; then
    echo "No models installed."
    return 0
  fi
  echo "The following models are installed:"
  echo "$names" | sed 's/^/  /'
  echo ""
  read -rp "DELETE ALL of them? Type YES to confirm (you would re-download to use any again): " ans
  case "$ans" in
    YES|yes) ;;
    *) echo "Aborted — nothing deleted."; return 0 ;;
  esac
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    "$OLLAMA_BIN" rm "$n" >/dev/null 2>&1 && echo "  removed: $n" || { echo "  FAILED: $n"; fails=$((fails+1)); }
  done <<< "$names"
  echo "Done (failures: $fails). Active model in .model still reads $MODEL, so task 4/21 would re-install it."
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

OC_TERMINAL="in this terminal"
[ -n "$KITTY_BIN" ] && OC_TERMINAL="in a new kitty window"

while true; do
  echo ""
echo "hello_llm_translate — local LLM agent ($MODEL)"
[ "$NEED_INSTALL" = "1" ] && echo "  !  Ollama not installed yet — run task 6"

echo "== server =="
echo "  1 Start Ollama server"
echo "  2 Status (server, active model, installed models, CPU/GPU)"
echo "  3 Stop server"
echo "  6 Install Ollama (only if not found)"

echo "== chat =="
echo "  5 Test chat"
echo "  7 Chat (interactive)"

echo "== models (installed as a <model>-64k variant with num_ctx baked) =="
echo "  4 Install active model"
echo "  16 Context-size report (built-in vs baked num_ctx)"
echo "  17 List all installed models (sizes + store location)"
echo "  18 Delete ALL installed models (destructive, needs a typed YES to run)"

echo "== opencode (local agent) =="
echo "  8 Launch opencode in a project dir — $OC_TERMINAL"
echo "  12 Install global opencode setup (rules + provider + default model in ~/.config/opencode)"
echo "  14 Show rules in effect (what a project loads; no launch)"
echo "  15 Install 'oc' launcher (~/.local/bin/oc: rules report, then opencode here)"
echo "  21 Load in qwen3:14b-64k   the working agent, reliable tool calls (~9 GB)"
echo "  9 Hardware analysis (OS/CPU/RAM/GPU)"

echo "  0 Exit"
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
    12) install_opencode_rules ;;
    14) show_rules ;;
    15) install_launcher ;;
    16) show_context ;;
    17) list_models ;;
    18) clear_models ;;
    20) echo "Removed — qwen3:14b-64k is the only agent." ;;
    21) use_model "qwen3:14b-64k" "the working agent, reliable tool calls" ;;
    22) echo "Removed — qwen3:14b-64k is the only agent." ;;
    0) break ;;
    *) echo "Unknown task" ;;
  esac
done
exit 0