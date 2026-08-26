"""Shared CSV schema + append helper for results/results.csv.

Both server.py (manual/browser-agent trials) and run_attack_suite.py
(automated Ollama trials) import FIELDNAMES and append_row from here so
every trial — human, browser agent, or local model — lands in one
comparable file.
"""
import csv
import os
import threading

RESULTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results")
RESULTS_CSV = os.path.join(RESULTS_DIR, "results.csv")

# condition: how the input was presented to the responder, e.g.
#   "raw_source"       - full HTML file source (Phase 1 default)
#   "vision_screenshot"- headless-rendered screenshot fed to a vision model (Phase 1b, run_vlm_suite.py)
#   "dom_extract"      - post-render DOM, scripts stripped (Phase 3)
#   "config_extract"   - serialized chart.data/chart.config for canvas libs (Phase 3)
#   "human"            - a person viewing the rendered page (log_form.html)
#   "browser_agent"    - a browser-driving agent (Claude in Chrome, etc.) viewing the rendered page
#
# correct: "true" / "false" / "needs_review" (ambiguous response, never guess-scored)
FIELDNAMES = [
    "timestamp",
    "library",
    "attack_id",
    "condition",
    "model",
    "question",
    "ground_truth",
    "response",
    "extracted_answer",
    "correct",
    "latency_ms",
    "notes",
]

_lock = threading.Lock()


def ensure_csv():
    os.makedirs(RESULTS_DIR, exist_ok=True)
    if not os.path.exists(RESULTS_CSV):
        with open(RESULTS_CSV, "w", newline="", encoding="utf-8") as f:
            csv.DictWriter(f, fieldnames=FIELDNAMES).writeheader()


def append_row(row: dict):
    """Append one row. Missing fields are written empty; unknown keys are dropped."""
    ensure_csv()
    clean = {k: row.get(k, "") for k in FIELDNAMES}
    with _lock:
        with open(RESULTS_CSV, "a", newline="", encoding="utf-8") as f:
            csv.DictWriter(f, fieldnames=FIELDNAMES).writerow(clean)


def read_rows():
    ensure_csv()
    with open(RESULTS_CSV, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))
