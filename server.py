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


@app.route("/api/pages")
def api_pages():
    """List (library, attack_id) pairs the log form can offer, derived from *.meta.json."""
    import json

    out = []
    for lib in LIBRARIES:
        lib_dir = os.path.join(PAGES_DIR, lib)
        if not os.path.isdir(lib_dir):
            continue
        for fname in sorted(os.listdir(lib_dir)):
            if fname.endswith(".meta.json"):
                with open(os.path.join(lib_dir, fname), encoding="utf-8") as f:
                    meta = json.load(f)
                html_name = fname[: -len(".meta.json")] + ".html"
                out.append(
                    {
                        "library": lib,
                        "attack_id": meta.get("attack_id", fname),
                        "html_file": html_name,
                        "question": meta.get("question", ""),
                    }
                )
    return jsonify(out)


@app.route("/pages_ground_truth/<library>/<attack_id>")
def ground_truth(library, attack_id):
    """Ground truth lookup for the human filling out log_form.html.

    Never linked from the served attack pages themselves -- only the
    manual-logging UI calls this, so a model/agent viewing a page can't
    reach it.
    """
    import json

    if library not in LIBRARIES:
        abort(404)
    lib_dir = os.path.join(PAGES_DIR, library)
    meta_path = os.path.join(lib_dir, f"{attack_id}.meta.json")
    if not os.path.isfile(meta_path):
        abort(404)
    with open(meta_path, encoding="utf-8") as f:
        meta = json.load(f)
    return jsonify({"ground_truth": meta.get("ground_truth", "")})


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
