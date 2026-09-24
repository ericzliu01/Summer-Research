#!/bin/bash
#SBATCH --job-name=vis_phase6_pilot
#SBATCH --partition=v100
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --gres=gpu:1
#SBATCH --time=6:00:00
#SBATCH --output=/users/5/liu02496/VisAgent/test/results/phase6_pilot_%j.log

set -e

# Phase 6 pilot: the 32 Tier A attacks (8 techniques x 4 libraries) in
# pages/<library>/attack_*, across two conditions:
#   - raw_source (run_attack_suite.py, text models) -- EXPECT ASR ~= 0.
#     Tier A attacks never touch the underlying data arrays, only how the
#     chart renders, so a model reading raw HTML/JS source sees the true
#     numbers regardless. This is a negative control confirming that, not
#     a test of whether the attacks work -- see README.md's "Phase 6"
#     section for the full rationale.
#   - multimodal_combined (run_multimodal_suite.py, vision models) --
#     genuinely open question. The model gets both the true source data
#     AND the misleading screenshot in the same prompt; this tests whether
#     having the source available lets it "see through" an attack it would
#     otherwise fall for under vision_screenshot alone (paused for now).
# No Playwright-scripted claude.ai/gemini.google.com automation here --
# that path is blocked by Cloudflare bot-detection on the Claude side (see
# conversation history / project memory), so this stays Ollama-only.
#
# multimodal_combined needs Playwright + a cached Chromium binary at
# PLAYWRIGHT_BROWSERS_PATH (compute nodes typically lack outbound internet
# to fetch it fresh). This uses the same PLAYWRIGHT_BROWSERS_PATH,
# `module load`, and PATH as run_multimodal_suite.slurm (already in this
# repo, pre-dating Phase 6) -- if that script has run successfully before,
# Chromium is already cached here and the Python env already has
# playwright/requests importable, so this should just work. If it's never
# been run successfully, `playwright install chromium` needs to happen
# against this same path from a login node (or other internet-connected
# machine) before submitting this job.

WORK_DIR=/users/5/liu02496/VisAgent/test
export PATH="$HOME/.local/bin:$HOME/ollama/bin:$PATH"
export OLLAMA_MODELS=/scratch.global/$USER/ollama-models
export PLAYWRIGHT_BROWSERS_PATH=/scratch.global/$USER/pw-browsers

echo "=== SLURM job $SLURM_JOB_ID on $(hostname) at $(date) ==="
nvidia-smi 2>/dev/null | grep -E "Tesla|Driver" | head -2 || echo "no nvidia-smi"

module load python/3.10.9_anaconda2023.03_libmamba

mkdir -p "$WORK_DIR/results"

nohup ollama serve > "$WORK_DIR/results/ollama_${SLURM_JOB_ID}.log" 2>&1 &
OLLAMA_PID=$!

for i in $(seq 1 60); do
    curl -s http://localhost:11434/api/tags > /dev/null 2>&1 && echo "Ollama ready after ${i}s" && break
    sleep 1
done

echo "=== Models already cached (pull is a no-op below if so) ==="
curl -s http://localhost:11434/api/tags | python3 -c "
import sys, json
d = json.load(sys.stdin)
for m in d.get('models', []):
    print(f\"  {m['name']}  ({m.get('size',0)//1024//1024} MB)\")
"

for MODEL in mistral:7b llama3:8b qwen2.5:7b llava:13b llama3.2-vision qwen2.5vl; do
    echo "=== Pulling $MODEL (skips if already cached) ==="
    ollama pull "$MODEL"
done

echo "=== Sanity check: mistral:7b responds ==="
curl -s --max-time 60 http://localhost:11434/api/generate \
    -d '{"model":"mistral:7b","prompt":"Say hi in one word","stream":false}' \
    | python3 -c "import sys,json; print('response:', json.load(sys.stdin).get('response','').strip())"

cd "$WORK_DIR"

echo ""
echo "=== results.csv row count before ==="
wc -l results/results.csv 2>/dev/null || echo "(no results.csv yet)"

echo ""
echo "=== raw_source: all 4 libraries, 32 Tier A attacks, 3 text models ==="
echo "=== Expect 192 new rows: 32 attacks x (1 attack + 1 clean_baseline) x 3 models ==="
python3 run_attack_suite.py --models mistral:7b,llama3:8b,qwen2.5:7b --timeout 120

echo ""
echo "=== multimodal_combined: all 4 libraries, 32 Tier A attacks, 3 vision models ==="
echo "=== Expect 192 new rows: 32 attacks x (1 attack + 1 clean_baseline) x 3 models ==="
python3 run_multimodal_suite.py --models llava:13b,llama3.2-vision,qwen2.5vl --timeout 180

echo ""
echo "=== results.csv row count after ==="
wc -l results/results.csv

echo ""
echo "=== Re-run both (everything should skip -- resumability check) ==="
python3 run_attack_suite.py --models mistral:7b,llama3:8b,qwen2.5:7b --timeout 120
python3 run_multimodal_suite.py --models llava:13b,llama3.2-vision,qwen2.5vl --timeout 180

echo ""
echo "=== Summary ==="
python3 summarize_results.py

echo ""
echo "=== Done at $(date) ==="
kill $OLLAMA_PID 2>/dev/null || true
