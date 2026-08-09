#!/bin/bash
#SBATCH --job-name=vis_attack_pilot
#SBATCH --partition=v100
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --gres=gpu:1
#SBATCH --time=2:00:00
#SBATCH --output=/users/5/liu02496/VisAgent/test/results/pilot_%j.log

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

echo "=== Sanity check ==="
curl -s --max-time 30 http://localhost:11434/api/generate \
    -d '{"model":"mistral:7b","prompt":"Say hi in one word","stream":false}' \
    | python3 -c "import sys,json; print('response:', json.load(sys.stdin).get('response','').strip())"

cd "$WORK_DIR"

echo ""
echo "=== Pilot run 1: d3, limit=5, mistral:7b ==="
python3 run_attack_suite.py --models mistral:7b --libraries d3 --limit 5 --timeout 120

echo ""
echo "=== results.csv row count (expect 11: 1 header + 10 rows) ==="
wc -l results/results.csv

echo ""
echo "=== Pilot run 2: all should skip ==="
python3 run_attack_suite.py --models mistral:7b --libraries d3 --limit 5 --timeout 120

echo ""
echo "=== results.csv row count after re-run (should be unchanged) ==="
wc -l results/results.csv

echo ""
echo "=== Summary ==="
python3 summarize_results.py

echo ""
echo "=== All results.csv rows ==="
cat results/results.csv

echo ""
echo "=== Done at $(date) ==="
kill $OLLAMA_PID 2>/dev/null || true
