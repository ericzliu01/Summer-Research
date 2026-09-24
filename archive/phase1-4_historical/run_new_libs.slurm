#!/bin/bash
#SBATCH --job-name=vis_attack_new_libs
#SBATCH --partition=v100
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --gres=gpu:1
#SBATCH --time=4:00:00
#SBATCH --output=/users/5/liu02496/VisAgent/test/results/new_libs_%j.log

set -e

WORK_DIR=/users/5/liu02496/VisAgent/test
export PATH="$HOME/ollama/bin:$PATH"
export OLLAMA_MODELS=/scratch.global/$USER/ollama-models

echo "=== SLURM job $SLURM_JOB_ID on $(hostname) at $(date) ==="
nvidia-smi 2>/dev/null | grep -E "Tesla|Driver" | head -2 || echo "no nvidia-smi"

mkdir -p "$WORK_DIR/results"

nohup ollama serve > "$WORK_DIR/results/ollama_${SLURM_JOB_ID}.log" 2>&1 &
OLLAMA_PID=$!

for i in $(seq 1 60); do
    curl -s http://localhost:11434/api/tags > /dev/null 2>&1 && echo "Ollama ready after ${i}s" && break
    sleep 1
done

cd "$WORK_DIR"

echo ""
echo "=== Run: all models, plotly, all attacks ==="
python3 run_attack_suite.py --models mistral:7b,llama3:8b,qwen2.5:7b --libraries plotly --timeout 120

echo ""
echo "=== Run: all models, chartjs, all attacks ==="
python3 run_attack_suite.py --models mistral:7b,llama3:8b,qwen2.5:7b --libraries chartjs --timeout 120

echo ""
echo "=== Run: all models, vega-lite, all attacks ==="
python3 run_attack_suite.py --models mistral:7b,llama3:8b,qwen2.5:7b --libraries vega-lite --timeout 120

echo ""
echo "=== Summary (all models, all libraries) ==="
python3 summarize_results.py

echo ""
echo "=== results.csv row count ==="
wc -l results/results.csv

echo ""
echo "=== Done at $(date) ==="
kill $OLLAMA_PID 2>/dev/null || true
