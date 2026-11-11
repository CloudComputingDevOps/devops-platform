#!/usr/bin/env bash
# R1.7 — Corre k6/wrk y cambia blue↔green a mitad de la prueba.
# Criterio: transición sin pérdida de requests (sin errores de conexión).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASE_URL="${BASE_URL:-http://gateway.local}"
TOOL="${TOOL:-k6}"          # k6 | wrk
DURATION_SEC="${DURATION_SEC:-60}"
SWITCH_AT="${SWITCH_AT:-20}" # segundos antes de hacer el switch
TARGET_COLOR="${1:-green}"

echo "==> Carga contra ${BASE_URL} con ${TOOL} durante ${DURATION_SEC}s"
echo "==> Switch a ${TARGET_COLOR} en t=${SWITCH_AT}s"

(
  sleep "${SWITCH_AT}"
  echo ""
  echo "==> [t=${SWITCH_AT}s] Ejecutando blue-green-switch -> ${TARGET_COLOR}"
  bash "${ROOT_DIR}/scripts/blue-green-switch.sh" "${TARGET_COLOR}"
) &
SWITCH_PID=$!

set +e
if [[ "${TOOL}" == "wrk" ]]; then
  BASE_URL="${BASE_URL}" DURATION="${DURATION_SEC}s" bash "${ROOT_DIR}/scripts/load/run-wrk.sh"
  RC=$?
else
  BASE_URL="${BASE_URL}" DURATION="${DURATION_SEC}s" VUS="${VUS:-10}" \
    bash "${ROOT_DIR}/scripts/load/run-k6.sh"
  RC=$?
fi
set -e

wait "${SWITCH_PID}" || true
echo "==> Prueba terminada (exit=${RC}). Revisa errores de conexión en la salida."
exit "${RC}"
