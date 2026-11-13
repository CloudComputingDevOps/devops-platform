#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
NS="${KUBE_NAMESPACE:-devops}"
TAG="${1:?Uso: blue-green-release.sh <tag> [blue|green]}"
FORCED="${2:-}"
CHART="./helm/microservices"
[[ "$TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || { echo 'Tag inválido' >&2; exit 1; }
ACTIVE="$(kubectl get svc gateway -n "$NS" -o jsonpath='{.spec.selector.version}')"
[[ "$ACTIVE" == blue || "$ACTIVE" == green ]] || { echo "Color activo inválido: $ACTIVE" >&2; exit 1; }
if [[ "$ACTIVE" == blue ]]; then CANDIDATE=green; else CANDIDATE=blue; fi
if [[ -n "$FORCED" ]]; then
  [[ "$FORCED" == "$CANDIDATE" ]] || { echo "Destino debe ser el inactivo ($CANDIDATE)" >&2; exit 1; }
fi
CURRENT_IMAGE="$(kubectl get deployment "gateway-$ACTIVE" -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}')"
REPO="${CURRENT_IMAGE%:*}"
[[ "$REPO" == ghcr.io/cloudcomputingdevops/gateway ]] || { echo "Repositorio inesperado: $REPO" >&2; exit 1; }
IMAGE="$REPO:$TAG"
echo "Activo=$ACTIVE | Candidato=$CANDIDATE | Imagen=$IMAGE"
# Reutiliza los valores de Helm existentes: NO reintroduce los tags viejos del archivo versionado.
helm upgrade microservices "$CHART" -n "$NS" --reuse-values \
  --set "blueGreen.activeColor=$ACTIVE" \
  --set-string "blueGreen.$CANDIDATE.tag=$TAG" \
  --wait --timeout 10m
kubectl rollout status "deployment/gateway-$CANDIDATE" -n "$NS" --timeout=180s
ACTUAL="$(kubectl get deployment "gateway-$CANDIDATE" -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}')"
[[ "$ACTUAL" == "$IMAGE" ]] || { echo "Imagen inesperada: $ACTUAL" >&2; exit 1; }
# Smoke test real contra el color candidato, ANTES del switch.
PORT="${SMOKE_LOCAL_PORT:-18080}"
PATH_TO_TEST="${SMOKE_PATH:-/}"
kubectl port-forward -n "$NS" "deployment/gateway-$CANDIDATE" "$PORT:3000" >/tmp/gateway-smoke-$$.log 2>&1 &
PF_PID=$!
cleanup() { kill "$PF_PID" 2>/dev/null || true; wait "$PF_PID" 2>/dev/null || true; rm -f /tmp/gateway-smoke-$$.log; }
trap cleanup EXIT
SMOKE_OK=false
for i in $(seq 1 25); do
  if ! kill -0 "$PF_PID" 2>/dev/null; then break; fi
  if curl -fsS --max-time 3 "http://127.0.0.1:$PORT$PATH_TO_TEST" >/dev/null; then SMOKE_OK=true; break; fi
  sleep 2
done
[[ "$SMOKE_OK" == true ]] || { echo "Smoke test falló en $CANDIDATE ($PATH_TO_TEST). Se conserva $ACTIVE" >&2; exit 1; }
cleanup
trap - EXIT
# Switch declarativo con Helm, para que el siguiente upgrade NO revierta el selector.
helm upgrade microservices "$CHART" -n "$NS" --reuse-values \
  --set "blueGreen.activeColor=$CANDIDATE" --wait --timeout 5m
SELECTOR="$(kubectl get svc gateway -n "$NS" -o jsonpath='{.spec.selector.version}')"
if [[ "$SELECTOR" != "$CANDIDATE" ]]; then
  echo "Selector incorrecto ($SELECTOR); revirtiendo a $ACTIVE" >&2
  helm upgrade microservices "$CHART" -n "$NS" --reuse-values --set "blueGreen.activeColor=$ACTIVE" --wait --timeout 5m || true
  exit 1
fi
echo "OK: $CANDIDATE activo con $IMAGE"
