<img src="hello_llm_translate.svg" alt="hello_llm_translate" width="120">

# hello_llm_translate

Example to translate with Large Language Models 

## Setup an Account at https://huggingface.co
* Get and Access Token, so the script can download all the models databases

## Setup the Environment 
```
poetry install
```
## Login to huggingface
```
poetry run hf auth login
```

## Example from English to German
```
cd Helsinki-NLP/opus-mt-en-de/
./main.py 
```

## Local LLM server (Ollama + qwen3:14b agent)
Run a CPU-only LLM API server on port 11434, usable directly by opencode and by
command-line chat (covers both the host and docker containers).
```
./ask.sh        # menu: start/stop server, install, pull model, test/chat
```

### `ask.sh` menu
```
  1  Start Ollama server      start serve (binds 0.0.0.0:11434)
  2  Status                   show server + installed models
  3  Stop server
  4  Pull model qwen3:14b  ~10 GB, one-time
  5  Test chat                send a test request (Thai "hello")
  6  Install Ollama           only needed if the ollama binary is missing
  7  Chat                     interactive chat (streams; /clear, /models, empty line to exit)
  8  OpenCode                 launch opencode in a project dir (prompt; default cwd) with the local model
  14 Show rules in effect     print which instructions/AGENTS.md files + models a project loads (no launch)
  15 Install 'oc' launcher    ~/.local/bin/oc — prints the rules report, then starts opencode in cwd
  9  Hardware analysis        show OS/kernel, CPU (cores + AVX flags), RAM, disk, GPU (nvidia-smi), pulled models
  10 Switch local model       pick a preset or type any model name (saved in .model)
  11 Download a model         pick a preset or type any name, then optionally make it active
  12 Install global setup     copy rules + merge ollama provider/models + default model into ~/.config/opencode (host-wide)
  13 Fix Ollama context      set num_ctx on every pulled model via /set parameter + /save
  0  Exit
```

On a new machine:
1. `./ask.sh`
2. Pick **6** to install Ollama (a missing binary shows a warning at the menu top; requires `curl`, needs `zstd` on Debian/Ubuntu)
3. Pick **4** to pull `qwen3:14b`
4. Pick **1** to start the server

Defaults & overrides:
- `BIND` (listen address) ← `OLLAMA_HOST`, default `0.0.0.0:11434` (reachable from containers/other hosts)
- `HOST` (client URL for status/test/chat) ← `HOST`, default `127.0.0.1:11434`; from a container use `HOST=192.168.43.2:11434`
- `OLLAMA_BIN` = path to the ollama binary (auto-detected: PATH, /usr/local/bin, /usr/bin, ~/.local/bin), `MODEL` = model name (default `qwen3:14b`, overridable with the `MODEL` env var; the last pick from task 10 is saved in `./.model` and wins unless `MODEL` is exported)

Notes:
- On the host, Ollama may be a systemd service (`ollama.service`) — `ask.sh` detects it and uses `systemctl` for start/stop/status; inside containers (no systemd) it falls back to manual `nohup` mode.
- Runtime files: PID/`.log`/`.model` → `./.ollama.pid`, `./.ollama.log`, `./.model` (gitignored).
- `opencode.json` registers the local models for opencode (default `ollama/qwen3:14b` as the agent, `baseURL http://127.0.0.1:11434/v1`); task 8 launches opencode with `--model ollama/$MODEL` in the chosen project dir. Restart opencode after changing `opencode.json`.
- **Which rules am I in?** Three ways:
  - Inside opencode: type **`/rules`** (installed globally by task 12). It is a custom command that injects the resolver output straight into the prompt (`` !`ask.sh --rules` ``) and asks the model to report it verbatim, so you see exactly which `instructions`, `AGENTS.md` chain, ollama models and default model that session loaded.
  - From a shell: `ask.sh --rules [dir]` (quiet, non-interactive; `ask.sh --help` for usage).
  - Before launching: task 8 prints the same report, and task 15 installs an `oc` launcher that does it every time.
- Task 12 also installs **two things that fight model stupidity**, both reported by `/rules`:
  - **`~/.config/opencode/AGENTS.md`** (a marked, auto-refreshed block; your own notes preserved). Auto-loaded in every session, so the ground rules land stronger than `instructions`: real working directory + real tool access, call `pwd` when asked where you are, exact tool names only (no `list`/`explore`/`execute`), act-then-explain, never spawn a subagent to answer a question about the session itself.
  - **`.opencode/plugins/session-env.js`** → copied to `~/.config/opencode/plugins/`. opencode already sends a minimal `<env>` block ("Working directory: …, Workspace root folder: …"), which `qwen3:14b` demonstrably ignores — it claims it has "no current folder". The plugin hooks `experimental.chat.system.transform` and appends a `<session-facts>` block (working directory, project root, project id, the real tool list, and an explicit "never claim you have no working directory"). Auto-loaded from the plugins dir, no config change needed.
- Recommended: `qwen3:14b` (classic function-calling, reliable tool calls with opencode) drives opencode as the agent. The CodeAct models `qwen3.6:35b-a3b` and `qwen3-coder:30b` are NOT reliable in opencode — they emit their own tool dialect (`<tool_code>print(...)` / `execute(...)`) instead of opencode's function calls — use them for chat or bulk code only. Switch with task 10.
- The base `qwen3*` models think first — replies come back empty if `max_tokens < 256` (ask.sh uses 512 for tests, 1024 for chat); reasoning shows in `reasoning_content` (qwen3.6 returns it in `reasoning`).
- Models reply in your language; tell them explicitly (e.g. "reply in English") if needed.
- **Project scope (opencode)**: Unlike this big-pickle agent that can move across directories via `workdir`, an opencode session is anchored to ONE project — and the working directory is **not** simply the folder you typed. From `Project.fromDirectory()`:
  1. It walks **up** from the launch dir looking for `.git`. If found, the session working directory becomes the **git repository root** (`git rev-parse --show-toplevel`) — not the subfolder you launched from. Launch in `grid/src/components` and you get `grid`.
  2. If no `.git` exists anywhere up the tree, it discards your folder and uses the hardcoded `worktree: "/"` "global" project (upstream bug #15719 / #24694) — the folder is not recognized at all. Fix: `git init` the folder (opencode also needs git for `/undo` and `/redo`).
  3. In a git worktree, sessions attach to the main repo (`--git-common-dir`) but the worktree becomes a "sandbox" of the same project.
  - So: verify with `ask.sh --rules` (it prints `cwd` and `project root` exactly as opencode resolves them) or type `/rules` inside a session.
  - To reach a folder outside the project mid-session: `/add-directory` (session-scoped, upstream) or allow it in config via `permission.external_directory` — e.g. `{"permission": {"external_directory": {"~/webs/code/**": "allow"}}}`. There are also community plugins with a true `/cd` (npm `opencode-dir`).
  - Launch it for a specific folder with the positional path: `opencode ~/webs/code/grid --model ollama/qwen3:14b` (task 8 does this for you, and offers `git init` if the folder is not a repo).
  - To reach a folder outside the project from inside a session: `/add-directory` (session-scoped, upstream) or allow it in config via `permission.external_directory` — e.g. `{"permission": {"external_directory": {"~/webs/code/**": "allow"}}}`. There are also community plugins with a true `/cd` (npm `opencode-dir`).
- **Context window (`num_ctx`) — run task 13** after pulling a model. Ollama defaults can be small (e.g. 4096), and opencode pushes its tool definitions at the end of the prompt — if the window is too small they get truncated and the model *denies having tools* (e.g. "I cannot execute shell commands"). Task 13 raises any model below the floor via `/set parameter num_ctx` + `/save` (`NUM_CTX=65536` recommended). It only *raises*; verify with `ollama show <model>`.
- **OpenCode needs 64k+ context.** Ollama's integration doc states it flatly, so the classic `qwen3*` agents (`qwen3:14b`, `8b`, `32b`) are registered with `limit.context: 65536`; use `NUM_CTX=65536 ./ask.sh` (task 13) so the model's own `num_ctx` matches. The CodeAct entries stay at 32768 — they are chat/bulk-code only, not agents.
- Some users report better local tool-calling with LM Studio, llama.cpp, or vLLM (`--tool-call-parser qwen3_coder --enable-auto-tool-choice`) instead of the Ollama backend.


## Extra Repository ##
```
 git remote add codeberg ssh://git@codeberg.org/veto/hello_llm_translate
 git push codeberg

```



