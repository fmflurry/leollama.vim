<div align="center">

<img src="assets/hero.png" alt="leollama.vim — a llama coding offline in Vim at a cozy desk, ethernet cable unplugged" width="100%"/>

# 🦙 leollama.vim

**Copilot-style inline AI autocomplete for classic Vim 9 — 100% local, 100% free.**

Powered by [Ollama](https://ollama.com) and fill-in-the-middle code models.
No API key. No subscription. No rate limits. Your code never leaves your machine.

[![Vim 9+](https://img.shields.io/badge/Vim-9.0%2B-019733?logo=vim&logoColor=white)](https://www.vim.org)
[![Ollama](https://img.shields.io/badge/Ollama-local-black?logo=ollama&logoColor=white)](https://ollama.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![No API key](https://img.shields.io/badge/API%20key-none%20needed-success)](#setup)
[![Privacy](https://img.shields.io/badge/your%20code-stays%20home-8A2BE2)](#why)

<br/>

```text
def fibonacci(n):
    if n <= 1:
        return n
    █return fibonacci(n - 2) + fibonacci(n - 1)   ← grey ghost text, <Tab> to accept
```

</div>

---

## ✨ Why

- 🔒 **Private** — completions are generated on your own machine; nothing is sent to any cloud.
- 💸 **Free forever** — no per-token billing, no free-tier rate limits, works offline on a plane.
- ⚡ **Fast** — ~300–800 ms warm on Apple Silicon with `qwen2.5-coder:7b-base`, thanks to Ollama's KV prompt caching and a deliberately tight context window.
- 🪶 **Zero bloat** — pure Vim script. Native virtual text (`+textprop`) and async jobs (`+job`). No Neovim required, no Node, no Python — only `curl`.

## 📦 Requirements

| What | Why |
|---|---|
| Vim **9.0.0067+** with `+textprop` and `+job` | ghost text & async requests |
| `curl` on `$PATH` | talks to the Ollama HTTP API |
| [Ollama](https://ollama.com) running locally | serves the model |
| A **FIM-capable** model | `qwen2.5-coder:7b-base`, `codellama:*-code`, `starcoder2`, … (qwen3:8b and qwen3-coder do NOT work — Ollama does not expose `suffix`/insert for them) |

Check your Vim:

```vim
:echo has('patch-9.0.0067') && has('textprop') && has('job')
```

## 🚀 Setup

**1.** Pull a fill-in-the-middle model (the default, ~4.7 GB):

```sh
ollama pull qwen2.5-coder:7b-base
```

**2.** Install the plugin with your favourite manager:

```vim
" vim-plug
Plug 'fmflurry/leollama.vim'
```

**3.** Open a file, enter insert mode, type. Grey ghost text appears after a short pause — `<Tab>` accepts, `<C-]>` dismisses. That's it. No API key, no account.

> [!TIP]
> The first suggestion after a cold start takes a few seconds while the model loads into memory. The plugin sends `keep_alive: 60m` with every request, so the model stays warm for your whole session.

## ⌨️ Usage

| Key / command | Action |
|---|---|
| `<Tab>` (insert mode) | accept the suggestion (falls through to a normal tab when none is shown) |
| `<C-]>` (insert mode) | dismiss the suggestion |
| `:LeOllamaToggle` | enable / disable for the session |
| `:LeOllamaDismiss` | clear the current suggestion |

## ⚙️ Configuration

All defaults, shown with their tuning rationale — see `:help leollama` for the full reference.

```vim
let g:leollama_model       = 'qwen2.5-coder:7b-base'   " FIM-capable Ollama model tag
let g:leollama_endpoint    = 'http://localhost:11434/api/generate'
let g:leollama_debounce_ms = 150     " idle time before a request fires
let g:leollama_max_lines   = 3       " ghost-text lines shown (0 = unlimited)
let g:leollama_max_tokens  = 64      " num_predict — ~4-5 lines, more is wasted GPU time
let g:leollama_max_prefix  = 2000    " bytes of code before the cursor
let g:leollama_max_suffix  = 1000    " bytes of code after the cursor
let g:leollama_temperature = 0.2
let g:leollama_stop        = ["\n\n\n"]
let g:leollama_keep_alive  = '60m'   " keep the model resident between requests
let g:leollama_accept_key  = '<Tab>'
```

### 🏎️ Speed vs. smarts

Prompt evaluation dominates local FIM latency — **context size is your throttle**:

| Want | Do |
|---|---|
| Faster | `ollama pull qwen2.5-coder:3b-base` + `let g:leollama_model = 'qwen2.5-coder:3b-base'`, lower `max_prefix`/`max_tokens` |
| Smarter | `ollama pull qwen2.5-coder:7b-base` + `let g:leollama_model = 'qwen2.5-coder:7b-base'`, raise `max_prefix` |

Measured on an M4 Pro (warm, typing steady-state): **3b ≈ 300–600 ms**, 7b ≈ 600–1200 ms.

## 🎨 Highlighting

- The model must support FIM — instruct/chat models (`llama3`, `gemma2`, …) return prose, not code fills.
- Quality tracks model size: a local 3b is not hosted-Copilot, but it's free and private.
- No streaming; one request per debounce window (stale requests are cancelled).
- If another completion plugin maps `<Tab>` (copilot.vim, codestral, …), set `g:leollama_accept_key` or load only one.

## 🧬 Lineage

Sibling of [lecodestral.vim](https://github.com/fmflurry/lecodestral.vim) (same engine, hosted Mistral Codestral backend). Pick your fighter: cloud quality or local freedom.

## 📄 License

[MIT](LICENSE) © Florian Michel (fmflurry)
