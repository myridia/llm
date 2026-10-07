<img src="llm.svg" alt="hello_llm_translate" width="120">

# hello_llm_translate

Local LLM toolkit: `ask.sh` manages a private **Ollama** model server on port
11434 and launches **opencode** with a local `qwen3:14b-64k` agent — fully
offline, no cloud API, no Hugging Face account.

## Requirements
- Linux host with ~12 GB+ free RAM (`qwen3:14b` needs ~9.3 GB model + KV cache)
- `curl`; on Debian/Ubuntu the Ollama installer also needs `zstd`
- opencode (optional — only needed for the agent launcher, tasks 8/15/21)

## Run locally (quick start)
```
./ask.sh                      # brings up the menu
```
1. **6** — install Ollama, if missing (a warning shows at the menu top)
2. **4** — install the working agent `qwen3:14b-64k` (pulls the base
   `qwen3:14b` and bakes the 64k-context variant automatically)
3. **1** — start the server
4. **2** — status check (server, active model, installed models, CPU/GPU)
5. **5** — test chat, or **7** for interactive chat
6. **8** — launch opencode in a project dir with the local agent (new kitty
   window; `KITTY_BIN=0 ./ask.sh` keeps it in the current terminal)

After that first setup it is just **1** start → **8** opencode.

## Local LLM server (Ollama + qwen3 agent)
OpenAI-compatible server on port 11434, usable directly by opencode and by
command-line chat (host and containers).

### `ask.sh` menu (grouped)
```
== server ==
  1 Start Ollama server
  2 Status (server, active model, installed models, CPU/GPU)
  3 Stop server
  6 Install Ollama (only if not found)

== chat ==
  5 Test chat
  7 Chat (interactive)

== models (installed as a <model>-64k variant with num_ctx baked) ==
  4  Install active model
  16 Context-size report (built-in vs baked num_ctx)
  17 List all installed models (sizes + store location)
  18 Delete ALL installed models (destructive, needs a typed YES to run)

== opencode (local agent) ==
  8  Launch opencode in a project dir (default cwd; new kitty window)
  12 Install global opencode setup (rules + provider + default model)
  14 Show rules in effect (no launch)
  15 Install 'oc' launcher (~/.local/bin/oc)
  21 Load in qwen3:14b-64k     the working agent (+ launch opencode)
  9  Hardware analysis

  0 Exit
```

How models get installed (task 4/21) — **numbered variants, not REPL saves**:
- `model_ensure "<name>"` builds a deterministic `<name>-64k` variant: `ollama show "<name>" --modelfile` → strip `num_ctx`/`PARAMETER` lines → append `PARAMETER num_ctx 65536` → `ollama create "<name>-64k"`. A plain raw name (no `<base>-<N>k` shape) falls through to `ollama pull`. This is why all models are used through `-64k` tags — the interactive `/set parameter num_ctx` + `/save` REPL path is unreliable on some builds (slash lines get fed to the model as chat), so task 4/21 bake the variant automatically on install. It only creates; it never rebuilds an existing variant and never lowers a window.

Defaults & overrides:
- `BIND` (listen address) ← `OLLAMA_HOST`, default `0.0.0.0:11434` (reachable from containers/other hosts)
- `HOST` (client URL for status/test/chat) ← `HOST`, default `127.0.0.1:11434`; from a container use `HOST=192.168.43.2:11434`
- `OLLAMA_BIN` = path to the ollama binary (auto-detected: PATH, /usr/local/bin, /usr/bin, ~/.local/bin), `MODEL` = model name (default `qwen3:14b-64k`, overridable with the `MODEL` env var; the active model is saved in `./.model` by task 21 and wins unless `MODEL` is exported)
- `CTX_FLOOR` = the 65536 window floor checked by task 16
- `KITTY_BIN` = terminal used for the opencode launch (task 8 and task 21), default `kitty`; set `KITTY_BIN=0` (or `none`) to run opencode in the current terminal instead. If kitty is not on PATH the launch falls back to the current terminal automatically, and menu line 8 says which one will be used.

Notes:
- On the host, Ollama may be a systemd service (`ollama.service`) — `ask.sh` detects it and uses `systemctl` for start/stop/status; inside containers (no systemd) it falls back to manual `nohup` mode.
- Runtime files: PID/`.log`/`.model` → `./.ollama.pid`, `./.ollama.log`, `./.model` (gitignored).
- `opencode.json` registers the local agent for opencode (default `ollama/qwen3:14b-64k`, `baseURL http://127.0.0.1:11434/v1`, `interleaved: { "field": "reasoning_content" }`, `temperature: 0.2`, `limit.context: 65536`); task 8 launches opencode with `--model ollama/$MODEL` in the chosen project dir, in a new kitty window (`kitty --single-instance --directory <proj> …`), so the ask.sh menu stays usable and the model runs in a terminal it owns. Restart opencode after changing `opencode.json`.
- **Which rules am I in?** Three ways:
  - Inside opencode: type **`/rules`** (installed globally by task 12). It is a custom command that injects the resolver output straight into the prompt (`` !`ask.sh --rules` ``) and asks the model to report it verbatim, so you see exactly which `instructions`, `AGENTS.md` chain, ollama models and default model that session loaded.
  - From a shell: `ask.sh --rules [dir]` (quiet, non-interactive; `ask.sh --help` for usage).
  - Before launching: task 8 prints the same report, and task 15 installs an `oc` launcher that does it every time.
- Task 12 also installs **two things that fight model stupidity**, both reported by `/rules`:
  - **`~/.config/opencode/AGENTS.md`** (a marked, auto-refreshed block; your own notes preserved). Auto-loaded in every session, so the ground rules land stronger than `instructions`: real working directory + real tool access, call `pwd` when asked where you are, exact tool names only (no `list`/`explore`/`execute`), act-then-explain, never spawn a subagent to answer a question about the session itself.
  - **`.opencode/plugins/session-env.js`** → copied to `~/.config/opencode/plugins/`. opencode already sends a minimal `<env>` block ("Working directory: …, Workspace root folder: …"), which a local model demonstrably ignores — it claims it has "no current folder". The plugin hooks `experimental.chat.system.transform` and appends a `<session-facts>` block (working directory, project root, project id, the real tool list, and an explicit "never claim you have no working directory"). Auto-loaded from the plugins dir, no config change needed.
- Recommended: `qwen3:14b-64k` (classic function-calling, reliable tool calls with opencode) drives opencode as the agent, and that is the **only** model in the config and menu — the 2026-09 wire capture showed classic `qwen3*` calls opencode's tools reliably, while CodeAct models (`qwen3.6:35b-a3b`, `qwen3-coder:30b`) emit their own tool dialect and are NOT reliable agents, and the other candidates (qwen3:8b/32b, deepseek-r1, qwen2.5-coder, deepseek-coder-v2, devstral) were removed — only `qwen3:14b-64k` is offered.
- The base `qwen3*` models think first — replies come back empty if `max_tokens < 256` (ask.sh uses 512 for tests, 1024 for chat); reasoning shows in a `reasoning_content` field, mapped via `interleaved`.
- Models reply in your language; tell them explicitly (e.g. "reply in English") if needed.
- **Project scope (opencode)**: Unlike this big-pickle agent that can move across directories via `workdir`, an opencode session is anchored to ONE project — and the working directory is **not** simply the folder you typed. From `Project.fromDirectory()`:
  1. It walks **up** from the launch dir looking for `.git`. If found, the session working directory becomes the **git repository root** (`git rev-parse --show-toplevel`) — not the subfolder you launched from. Launch in `grid/src/components` and you get `grid`.
  2. If no `.git` exists anywhere up the tree, it discards your folder and uses the hardcoded `worktree: "/"` "global" project (upstream bug #15719 / #24694) — the folder is not recognized at all. Fix: `git init` the folder (opencode also needs git for `/undo` and `/redo`).
  3. In a git worktree, sessions attach to the main repo (`--git-common-dir`) but the worktree becomes a "sandbox" of the same project.
  - So: verify with `ask.sh --rules` (it prints `cwd` and `project root` exactly as opencode resolves them) or type `/rules` inside a session.
  - Launch it for a specific folder with the positional path: `opencode ~/webs/code/grid --model ollama/qwen3:14b-64k` (task 8 does this for you, and offers `git init` if the folder is not a repo).
  - To reach a folder outside the project mid-session: `/add-directory` (session-scoped, upstream) or allow it in config via `permission.external_directory` — e.g. `{"permission": {"external_directory": {"~/webs/code/**": "allow"}}}`. There are also community plugins with a true `/cd` (npm `opencode-dir`).
- **Context window (`num_ctx`)** — Ollama's built-in window on `qwen3*` is 40960, and opencode pushes its tool definitions at the end of the prompt — if the window is too small they get truncated and the model *denies having tools* (e.g. "I cannot execute shell commands"). That is why models are always installed as `-64k` variants (task 4/21: `model_ensure` bakes `PARAMETER num_ctx 65536` via Modelfile + `ollama create`). Verify with task 16 — variant tags show `NUM_CTX` 65536 (`ollama show <model>` prints the built-in `Context Length`; the baked override is `ollama show --parameters <name>-64k`).
- **OpenCode needs 64k+ context.** Ollama's integration doc states it flatly, so every agent is used through a `-64k` variant matching `limit.context: 65536`.
- Some users report better local tool-calling with LM Studio, llama.cpp, or vLLM (`--tool-call-parser qwen3_coder --enable-auto-tool-choice`) instead of the Ollama backend.


## Extra Repository ##
```
 git remote add codeberg ssh://git@codeberg.org/veto/hello_llm_translate
 git push codeberg

```



