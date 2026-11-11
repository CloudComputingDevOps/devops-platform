#!/usr/bin/env bash
# Ejecuta la prueba k6 del Gateway.
# Uso:
#   ./scripts/load/run-k6.sh
#   BASE_URL=http://127.0.0.1:3000 VUS=20 DURATION=90s ./scripts/load/run-k6.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/scripts/load/results"
mkdir -p "${RESULTS_DIR}"

if ! command -v k6 >/dev/null 2>&1; then
  cat >&2 <<'EOF'
k6 no está instalado.
Ubuntu (ejemplo):
  sudo gpg -k
  sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
    --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
  echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
    | sudo tee /etc/apt/sources.list.d/k6.list
  sudo apt-get update && sudo apt-get install -y k6
EOF
  exit 1
fi

export BASE_URL="${BASE_URL:-http://gateway.local}"
export REQUEST_PATH="${REQUEST_PATH:-/}"
export VUS="${VUS:-10}"
export DURATION="${DURATION:-60s}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${RESULTS_DIR}/k6-${STAMP}.json"

echo "==> k6 BASE_URL=${BASE_URL} REQUEST_PATH=${REQUEST_PATH} VUS=${VUS} DURATION=${DURATION}"
k6 run --summary-export="${OUT}" "${ROOT_DIR}/scripts/load/gateway-k6.js"
echo "==> Resumen exportado a ${OUT}"
