#!/bin/bash
#SBATCH --job-name=vis_dual_agent
#SBATCH --partition=v100
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --gres=gpu:1
#SBATCH --time=20:00:00
#SBATCH --output=/users/5/liu02496/VisAgent/test/results/dual_agent_%j.log

set -e

WORK_DIR=/users/5/liu02496/VisAgent/test
export PATH="$HOME/.local/bin:$HOME/ollama/bin:$PATH"
export OLLAMA_MODELS=/scratch.global/$USER/ollama-models
export PLAYWRIGHT_BROWSERS_PATH=/scratch.global/$USER/pw-browsers

echo "=== SLURM job $SLURM_JOB_ID on $(hostname) at $(date) ==="
nvidia-smi 2>/dev/null | grep -E "Tesla|Driver" | head -2 || echo "no nvidia-smi"

module load python/3.10.9_anaconda2023.03_libmamba

mkdir -p "$WORK_DIR/results"

# Start Ollama
nohup ollama serve > "$WORK_DIR/results/ollama_${SLURM_JOB_ID}.log" 2>&1 &
OLLAMA_PID=$!

for i in $(seq 1 60); do
    curl -s http://localhost:11434/api/tags > /dev/null 2>&1 && echo "Ollama ready after ${i}s" && break
    sleep 1
done

# Pull models (skips if already cached)
echo "=== Pulling vision model ==="
ollama pull qwen2.5vl

echo "=== Pulling source models ==="
ollama pull qwen2.5:7b
ollama pull llama3:8b

echo "=== Sanity check: qwen2.5vl responds ==="
curl -s --max-time 60 http://localhost:11434/api/generate \
    -d '{"model":"qwen2.5vl","prompt":"Say hi in one word","stream":false}' \
    | python3 -c "import sys,json; print('response:', json.load(sys.stdin).get('response','').strip())"

cd "$WORK_DIR"

echo ""
echo "=== Run 1: qwen2.5vl (vision) + qwen2.5:7b (source) ==="
python3 run_dual_agent_suite.py \
    --vision-model qwen2.5vl \
    --source-model qwen2.5:7b \
    --timeout 240

echo ""
echo "=== Run 2: qwen2.5vl (vision) + llama3:8b (source) ==="
python3 run_dual_agent_suite.py \
    --vision-model qwen2.5vl \
    --source-model llama3:8b \
    --timeout 240

echo ""
echo "=== results.csv row count ==="
wc -l results/results.csv

echo ""
echo "=== Summary ==="
python3 summarize_results.py

echo ""
echo "=== Done at $(date) ==="
kill $OLLAMA_PID 2>/dev/null || true
