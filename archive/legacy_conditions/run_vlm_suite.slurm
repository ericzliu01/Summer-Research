#!/bin/bash
#SBATCH --job-name=vis_vlm_suite
#SBATCH --partition=v100
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --gres=gpu:1
#SBATCH --time=12:00:00
#SBATCH --output=/users/5/liu02496/VisAgent/test/results/vlm_%j.log

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

# Pull vision models if not already cached
for MODEL in llava:13b llama3.2-vision qwen2.5vl; do
    echo "=== Pulling $MODEL (skips if already cached) ==="
    ollama pull "$MODEL"
done

echo "=== Sanity check: llava:13b responds ==="
curl -s --max-time 60 http://localhost:11434/api/generate \
    -d '{"model":"llava:13b","prompt":"Say hi in one word","stream":false}' \
    | python3 -c "import sys,json; print('response:', json.load(sys.stdin).get('response','').strip())"

cd "$WORK_DIR"

echo ""
echo "=== VLM suite: all libraries, all vision models ==="
python3 run_vlm_suite.py --models llava:13b,llama3.2-vision,qwen2.5vl --timeout 120

echo ""
echo "=== results.csv row count ==="
wc -l results/results.csv

echo ""
echo "=== Summary ==="
python3 summarize_results.py

echo ""
echo "=== Done at $(date) ==="
kill $OLLAMA_PID 2>/dev/null || true
