# Prompt for Claude Code running on the MSI side

Paste this into Claude Code once it's running on the MSI host (e.g. `ahl04`),
in the `VisAgent/test` (or wherever this repo landed) directory.

---

I need you to get a local Ollama server running on this machine and validate
an existing automated test pipeline against it, starting with a small pilot
(one library, a handful of attacks) before we scale up to the full attack
set. Work through this step by step, checking each thing before moving to
the next, and report back clearly what worked, what didn't, and any
decisions you had to make.

## 1. Environment check

- Am I on a login node or a compute node? (`hostname`, and check for any
  SLURM env vars like `$SLURM_JOB_ID` to tell.)
- Do I have outbound internet from here? Test with
  `curl -sI https://ollama.com --max-time 5` and
  `curl -sI https://registry.ollama.ai --max-time 5`. If this node has no
  internet but a login node does, tell me now rather than proceeding —
  installing/pulling models may need to happen from the login node instead,
  with model weights cached somewhere both nodes can read (shared home,
  project, or scratch storage).
- Do I have passwordless sudo? Check with `sudo -n true 2>/dev/null && echo yes || echo no`.
- How much space is available in `$HOME` vs. any project/scratch storage
  (`df -h ~`, and check for `$SCRATCH`/`/project` type paths this cluster
  uses)? Ollama models are multi-GB each; if home has a small quota, models
  need to live elsewhere via `OLLAMA_MODELS`.

## 2. Install Ollama

- If sudo is available, use the standard installer:
  `curl -fsSL https://ollama.com/install.sh | sudo sh`
- If not, install the standalone Linux tarball into `$HOME` with no root
  needed:
  ```bash
  curl -L https://ollama.com/download/ollama-linux-amd64.tgz -o /tmp/ollama.tgz
  mkdir -p ~/ollama
  tar -xzf /tmp/ollama.tgz -C ~/ollama
  export PATH="$HOME/ollama/bin:$PATH"
  ```
  Add the PATH export to `~/.bashrc` if it works, so it persists across
  sessions.
- Verify with `ollama --version`.

## 3. Configure model storage

- If using project/scratch storage instead of `$HOME` (per the space check
  above), set `export OLLAMA_MODELS=/path/to/that/storage/ollama-models`
  before starting the server, and `mkdir -p` that directory first. Add this
  export to `~/.bashrc` too if it's going to be used repeatedly.

## 4. Start the server and pull models

- There's likely no systemd without root, so start it manually:
  `nohup ollama serve > ~/ollama.log 2>&1 &`
- Confirm it's up: `curl -s http://localhost:11434/api/tags`
- Pull the three models the harness defaults to:
  `ollama pull mistral:7b`, `ollama pull llama3:8b`, `ollama pull qwen2.5:7b`
  — start with just `mistral:7b` first, don't pull all three until step 5
  below succeeds.
- Sanity check one model actually answers:
  ```bash
  curl http://localhost:11434/api/generate -d '{"model": "mistral:7b", "prompt": "Say hi in one word", "stream": false}'
  ```

## 5. Run and validate the pilot pipeline

This directory has an existing harness: `run_attack_suite.py` sends each
`pages/<library>/*.html` page (that has a matching `.meta.json`) to Ollama's
`/api/generate` along with a fixed question, grades the reply against
`ground_truth`, and logs to `results/results.csv`. `summarize_results.py`
turns that into ASR (attack success rate) tables. There are 49 attack pages
across 4 libraries total (d3, plotly, chartjs, vega-lite) — for this pilot
we're deliberately running a small slice first, not the full set.

- `pip install flask requests` if not already available (check with
  `python3 -c "import flask, requests"` first).
- Run: `python3 run_attack_suite.py --models mistral:7b --libraries d3 --limit 5 --timeout 60`
  (`--limit 5` caps it to the first 5 attack pages in the d3 library —
  `attack_01` through `attack_05` — so this makes 10 requests total: one per
  attack plus one clean baseline per attack, all against `mistral:7b`.)
- Confirm it doesn't crash partway through, and that `results/results.csv`
  actually gets rows appended (`wc -l results/results.csv` — expect 11 lines:
  1 header + 10 trials).
- Re-run the exact same command a second time — it should skip every
  combo it already logged (look for `[skip] ... (already logged)` in the
  output) rather than re-querying Ollama. This resumability is required for
  later SLURM use (a killed/requeued job shouldn't redo completed work).
- Run `python3 summarize_results.py` and look at the printed tables /
  `results/summary.md`. Sanity-check a few rows of `results.csv` by eye —
  does `correct` look right given the `response` text? Flag anything where
  the grading (numeric ±1% tolerance, case-insensitive substring for
  categorical, `needs_review` when no clear answer is extractable) seems to
  be misjudging real model output — that's useful signal for tuning the
  grader, distinct from the model just getting attacks wrong.
- Only once this pilot looks clean, consider scaling up: drop `--limit` to
  cover all d3 attacks, add more `--libraries`, or add more `--models` —
  one dimension at a time so it's clear what any new failure came from.

## 6. Report back

Tell me:
- Whether login vs. compute node had internet, and what you had to do
  about it if not.
- Whether sudo was available and which install path you took.
- Where models ended up living (home vs. scratch/project) and why.
- The `results/summary.md` output after the `mistral:7b` pilot run (d3,
  5 attacks).
- Any grading mismatches you spotted by manually checking a sample of rows.
- Anything in the harness that broke or needs a fix before scaling up
  (more attacks within d3, then the other libraries, then the other two
  default models).
