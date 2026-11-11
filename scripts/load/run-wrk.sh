#!/usr/bin/env bash
# Prueba de carga con wrk.
# Uso:
#   ./scripts/load/run-wrk.sh
#   BASE_URL=http://127.0.0.1:3000 THREADS=4 CONNECTIONS=50 DURATION=60s ./scripts/load/run-wrk.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/scripts/load/results"
mkdir -p "${RESULTS_DIR}"

BASE_URL="${BASE_URL:-http://gateway.local}"
PATH_SUFFIX="${PATH_SUFFIX:-/api/areas}"
THREADS="${THREADS:-2}"
CONNECTIONS="${CONNECTIONS:-20}"
DURATION="${DURATION:-30s}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${RESULTS_DIR}/wrk-${STAMP}.txt"

if ! command -v wrk >/dev/null 2>&1; then
  echo "wrk no está instalado. En Ubuntu: sudo apt-get install -y wrk" >&2
  exit 1
fi

TARGET="${BASE_URL%/}${PATH_SUFFIX}"
echo "==> wrk ${THREADS} threads, ${CONNECTIONS} connections, ${DURATION} -> ${TARGET}"
wrk -t"${THREADS}" -c"${CONNECTIONS}" -d"${DURATION}" --latency "${TARGET}" | tee "${OUT}"
echo "==> Resultado guardado en ${OUT}"
