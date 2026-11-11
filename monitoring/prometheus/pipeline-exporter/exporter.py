#!/usr/bin/env python3
"""Exportador de metricas del pipeline CI (GitHub Actions) para Prometheus.

Los workflows corren en runners de GitHub, que no pueden llegar al cluster de
Minikube dentro de la VM. Por eso este proceso hace lo contrario: desde el
cluster consulta la API de GitHub cada cierto tiempo y publica el resultado en
/metrics, de donde lo recoge Prometheus (R1.4: duracion de builds y tasa de exito).

Solo usa la libreria estandar de Python, asi que corre sobre la imagen oficial
python sin construir una imagen propia.
"""
import json
import os
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ORG = os.environ.get("GITHUB_ORG", "CloudComputingDevOps")
REPOS = [r.strip() for r in os.environ.get("GITHUB_REPOS", "").split(",") if r.strip()]
TOKEN = os.environ.get("GITHUB_TOKEN", "").strip()
API_URL = os.environ.get("GITHUB_API_URL", "https://api.github.com").rstrip("/")
WINDOW = int(os.environ.get("RUNS_WINDOW", "30"))
# Sin token GitHub permite 60 consultas por hora; con token, 5000.
POLL_SECONDS = int(os.environ.get("POLL_SECONDS", "60" if TOKEN else "600"))
PORT = int(os.environ.get("PORT", "9101"))

_lock = threading.Lock()
_body = "# El exportador aun no ha consultado la API de GitHub\n"


def _parse(ts):
    return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").timestamp()


def fetch_runs(repo):
    url = f"{API_URL}/repos/{ORG}/{repo}/actions/runs?status=completed&per_page={WINDOW}"
    req = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "ci-pipeline-exporter",
    })
    if TOKEN:
        req.add_header("Authorization", f"Bearer {TOKEN}")
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.load(resp).get("workflow_runs", [])


def summarize(runs):
    """Resume los runs (ordenados del mas reciente al mas antiguo) en numeros."""
    counts = {}
    durations = []
    for run in runs:
        conclusion = run.get("conclusion") or "unknown"
        counts[conclusion] = counts.get(conclusion, 0) + 1
        if conclusion in ("success", "failure") and run.get("run_started_at"):
            durations.append(max(0.0, _parse(run["updated_at"]) - _parse(run["run_started_at"])))

    # Para la tasa de exito solo cuentan los runs que terminaron bien o mal;
    # los cancelados y omitidos no dicen nada sobre la calidad del build.
    judged = [r for r in runs if r.get("conclusion") in ("success", "failure")]
    consecutive = 0
    for run in judged:
        if run["conclusion"] != "failure":
            break
        consecutive += 1

    summary = {"counts": counts, "consecutive_failures": consecutive}
    if judged:
        last = judged[0]
        ok = sum(1 for r in judged if r["conclusion"] == "success")
        summary.update({
            "success_ratio": ok / len(judged),
            "avg_duration": sum(durations) / len(durations) if durations else 0.0,
            "last_success": 1 if last["conclusion"] == "success" else 0,
            "last_duration": max(0.0, _parse(last["updated_at"]) - _parse(last["run_started_at"])),
            "last_timestamp": _parse(last["updated_at"]),
        })
    return summary


HELP = {
    "ci_workflow_last_run_duration_seconds": "Duracion del ultimo run terminado del pipeline",
    "ci_workflow_avg_duration_seconds": "Duracion promedio de los ultimos runs del pipeline",
    "ci_workflow_last_run_success": "1 si el ultimo run termino bien, 0 si fallo",
    "ci_workflow_last_run_timestamp_seconds": "Momento en que termino el ultimo run (epoch)",
    "ci_workflow_success_ratio": "Fraccion de runs exitosos en la ventana reciente (0 a 1)",
    "ci_workflow_consecutive_failures": "Runs fallidos seguidos, contando desde el mas reciente",
    "ci_workflow_runs": "Cantidad de runs en la ventana reciente por resultado",
    "ci_exporter_up": "1 si la ultima consulta a la API de GitHub para el repo funciono",
}


def render(results):
    lines = {name: [] for name in HELP}
    for repo, (summary, ok) in sorted(results.items()):
        label = f'repo="{repo}"'
        lines["ci_exporter_up"].append(f"ci_exporter_up{{{label}}} {1 if ok else 0}")
        if not summary:
            continue
        for conclusion, count in sorted(summary["counts"].items()):
            lines["ci_workflow_runs"].append(
                f'ci_workflow_runs{{{label},conclusion="{conclusion}"}} {count}')
        lines["ci_workflow_consecutive_failures"].append(
            f"ci_workflow_consecutive_failures{{{label}}} {summary['consecutive_failures']}")
        if "success_ratio" in summary:
            for metric, key in (
                ("ci_workflow_last_run_duration_seconds", "last_duration"),
                ("ci_workflow_avg_duration_seconds", "avg_duration"),
                ("ci_workflow_last_run_success", "last_success"),
                ("ci_workflow_last_run_timestamp_seconds", "last_timestamp"),
                ("ci_workflow_success_ratio", "success_ratio"),
            ):
                lines[metric].append(f"{metric}{{{label}}} {summary[key]}")
    out = []
    for name, samples in lines.items():
        if samples:
            out.append(f"# HELP {name} {HELP[name]}")
            out.append(f"# TYPE {name} gauge")
            out.extend(samples)
    return "\n".join(out) + "\n"


def poll_forever():
    global _body
    results = {}
    while True:
        for repo in REPOS:
            try:
                results[repo] = (summarize(fetch_runs(repo)), True)
            except (urllib.error.URLError, ValueError, KeyError, TimeoutError) as err:
                print(f"[exporter] error consultando {repo}: {err}", flush=True)
                # Se conserva el ultimo dato bueno y se marca el repo como no disponible.
                results[repo] = (results.get(repo, (None, False))[0], False)
        with _lock:
            _body = render(results)
        time.sleep(POLL_SECONDS)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.split("?")[0] not in ("/metrics", "/"):
            self.send_error(404)
            return
        with _lock:
            payload = _body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    if not REPOS:
        raise SystemExit("Falta la variable GITHUB_REPOS (lista separada por comas)")
    print(f"[exporter] org={ORG} repos={REPOS} cada {POLL_SECONDS}s, token={'si' if TOKEN else 'no'}", flush=True)
    threading.Thread(target=poll_forever, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
