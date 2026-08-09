#!/bin/bash
#SBATCH --job-name=vis_pilot_cpu
#SBATCH --partition=amdsmall
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=64G
#SBATCH --time=4:00:00
#SBATCH --output=/users/5/liu02496/VisAgent/test/results/pilot_cpu_%j.log

set -e

WORK_DIR=/users/5/liu02496/VisAgent/test
export PATH="$HOME/ollama/bin:$PATH"
export OLLAMA_MODELS=/scratch.global/$USER/ollama-models
export OLLAMA_NUM_THREADS=${SLURM_CPUS_PER_TASK}
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK}

echo "=== SLURM job $SLURM_JOB_ID on $(hostname) at $(date) ==="
echo "CPUs: $SLURM_CPUS_PER_TASK  MEM: 64G  (CPU-only fallback)"

mkdir -p "$WORK_DIR/results"

# Start Ollama server
nohup ollama serve > "$WORK_DIR/results/ollama_cpu_${SLURM_JOB_ID}.log" 2>&1 &
OLLAMA_PID=$!
echo "Ollama server PID: $OLLAMA_PID"

for i in $(seq 1 60); do
    curl -s http://localhost:11434/api/tags > /dev/null 2>&1 && echo "Ollama ready after ${i}s" && break
    sleep 1
done

echo "Available models:"
curl -s http://localhost:11434/api/tags | python3 -c "
import sys, json
d = json.load(sys.stdin)
for m in d.get('models', []):
    print(f\"  {m['name']}  ({m.get('size',0)//1024//1024} MB)\")
"

# Sanity check — no timeout cap, let model warm up however long it needs
echo "=== Sanity check (warming model — may take several minutes on CPU) ==="
start=$SECONDS
curl -s http://localhost:11434/api/generate \
    -d '{"model":"mistral:7b","prompt":"Say hi in one word","stream":false}' \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print('response:', d.get('response','').strip())"
echo "Sanity check took $((SECONDS - start))s"

# Full d3 pilot (attacks 01-03 missing; 04-05 already done and will skip)
echo ""
echo "=== Full d3 pilot: d3, limit=5, mistral:7b, timeout=300s ==="
cd "$WORK_DIR"
python3 run_attack_suite.py --models mistral:7b --libraries d3 --limit 5 --timeout 300

echo ""
echo "=== results.csv row count (expect 11: 1 header + 10 rows) ==="
wc -l results/results.csv

echo ""
echo "=== Re-run (all should skip) ==="
python3 run_attack_suite.py --models mistral:7b --libraries d3 --limit 5 --timeout 300

echo ""
echo "=== Summary ==="
python3 summarize_results.py

echo ""
echo "=== All results.csv rows ==="
cat results/results.csv

echo ""
echo "=== Done at $(date) ==="
kill $OLLAMA_PID 2>/dev/null || true
