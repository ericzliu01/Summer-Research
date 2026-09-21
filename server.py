"""Flask app serving the vis-attack pages and accepting manual trial logs.

Run:  python server.py
Then open http://localhost:5000/ for an index, or http://localhost:5000/log_form.html
to log a manual/browser-agent trial after viewing a page.

Never serves *.meta.json (ground truth) alongside the page a model/human
looks at -- those are for scoring only.
"""
import os
import time

from flask import Flask, jsonify, request, send_from_directory, abort

from results_logger import FIELDNAMES, append_row
from run_attack_suite import discover_pages

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PAGES_DIR = os.path.join(BASE_DIR, "pages")
LIBRARIES = ["d3", "plotly", "chartjs", "vega-lite"]

app = Flask(__name__, static_folder=None)


@app.route("/")
def index():
    links = []
    for lib in LIBRARIES:
        lib_dir = os.path.join(PAGES_DIR, lib)
        if not os.path.isdir(lib_dir):
            continue
        for fname in sorted(os.listdir(lib_dir)):
            if fname.endswith(".html"):
                links.append(f'<li><a href="/pages/{lib}/{fname}">{lib}/{fname}</a></li>')
    body = "<h1>vis-attack pages</h1><ul>" + "".join(links) + "</ul>"
    body += '<p><a href="/log_form.html">Log a manual trial</a></p>'
    return body


@app.route("/pages/<library>/<path:filename>")
def serve_page(library, filename):
    if library not in LIBRARIES:
        abort(404)
    if filename.endswith(".meta.json"):
        # ground truth is for scoring only, never served to a model/viewer
        abort(404)
    lib_dir = os.path.join(PAGES_DIR, library)
    if not os.path.isfile(os.path.join(lib_dir, filename)):
        abort(404)
    return send_from_directory(lib_dir, filename)


@app.route("/log_form.html")
def log_form():
    return send_from_directory(BASE_DIR, "log_form.html")


CLEAN_BASELINE_SUFFIX = "__clean_baseline"


@app.route("/api/pages")
def api_pages():
    """List (library, attack_id) pairs the log form can offer.

    Reuses run_attack_suite.py's discover_pages() rather than re-scanning
    meta.json files directly, so this stays in sync with however attacks
    and clean baselines are paired for the automated runners. For each
    attack, also offers a synthetic "<attack_id>__clean_baseline" entry --
    that attack's clean_<chart_type> page, but asking the ATTACK's question
    (not the clean page's own default Retrieve Value question) -- because
    that's what run_attack_suite.py/run_vlm_suite.py actually log for ASR:
    the same question against both the attack and its clean counterpart.
    Without this, a human filling out the form for a clean-baseline trial
    would see the wrong (auto-filled) question unless they manually
    overrode it.
    """
    clean_by_key, attacks = discover_pages()
    out = []
    for (library, _chart_type), entry in sorted(clean_by_key.items()):
        out.append({
            "library": library,
            "attack_id": entry["attack_id"],
            "html_file": os.path.basename(entry["html_path"]),
            "question": entry["question"],
        })
    for attack in attacks:
        out.append({
            "library": attack["library"],
            "attack_id": attack["attack_id"],
            "html_file": os.path.basename(attack["html_path"]),
            "question": attack["question"],
        })
        clean = clean_by_key.get((attack["library"], attack["chart_type"]))
        if clean is not None:
            out.append({
                "library": attack["library"],
                "attack_id": f"{attack['attack_id']}{CLEAN_BASELINE_SUFFIX}",
                "html_file": os.path.basename(clean["html_path"]),
                "question": attack["question"],
            })
    return jsonify(out)


@app.route("/pages_ground_truth/<library>/<attack_id>")
def ground_truth(library, attack_id):
    """Ground truth lookup for the human filling out log_form.html.

    Never linked from the served attack pages themselves -- only the
    manual-logging UI calls this, so a model/agent viewing a page can't
    reach it. A "<attack_id>__clean_baseline" id (see api_pages above)
    resolves to the underlying attack's ground truth, since it's the same
    question asked against the clean page instead of the attack page.
    """
    if library not in LIBRARIES:
        abort(404)
    real_attack_id = attack_id
    if attack_id.endswith(CLEAN_BASELINE_SUFFIX):
        real_attack_id = attack_id[: -len(CLEAN_BASELINE_SUFFIX)]
    clean_by_key, attacks = discover_pages()
    for entry in attacks:
        if entry["library"] == library and entry["attack_id"] == real_attack_id:
            return jsonify({"ground_truth": entry["ground_truth"]})
    for (lib, _chart_type), entry in clean_by_key.items():
        if lib == library and entry["attack_id"] == attack_id:
            return jsonify({"ground_truth": entry["ground_truth"]})
    abort(404)


@app.route("/log", methods=["POST"])
def log():
    data = request.get_json(force=True, silent=True) or {}
    row = {k: data.get(k, "") for k in FIELDNAMES}
    if not row.get("timestamp"):
        row["timestamp"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    append_row(row)
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
