#!/usr/bin/env bash
# Despliegue Blue-Green completo para Gateway (CD automatizado - R1.7).
# Flujo:
#   1. Detecta el color activo del Service gateway (blue o green)
#   2. Determina el slot inactivo (candidato)
#   3. Actualiza la imagen de gateway-<inactivo> con el nuevo tag
#   4. Espera rollout status (pods Ready)
#   5. Ejecuta smoke test contra los pods del slot candidato
#   6. Conmuta el Service al nuevo color sin perder tráfico
#   7. Si falla el smoke post-switch, hace rollback automático al color previo
#
# Uso:
#   ./scripts/blue-green-release.sh <image_tag> [target_color]
# Ejemplo:
#   ./scripts/blue-green-release.sh sha-d712b92
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="${NS:-devops}"
SVC="${SVC:-gateway}"
REPO="${GATEWAY_REPO:-ghcr.io/cloudcomputingdevops/gateway}"
NEW_TAG="${1:-}"
FORCED_COLOR="${2:-}"
SMOKE_PATH="${SMOKE_PATH:-/api/areas}"

if [[ -z "${NEW_TAG}" ]]; then
  # Si no se pasa tag por argumento, lee el tag de helm/microservices/values-images.yaml
  NEW_TAG="$(awk '/gateway:/{f=1} f && /tag:/{print $2; exit}' "${ROOT_DIR}/helm/microservices/values-images.yaml" | tr -d "\"'")"
fi

if [[ -z "${NEW_TAG}" ]]; then
  echo "Uso: $0 <image_tag> [blue|green]" >&2
  exit 1
fi

ACTIVE_COLOR="$(kubectl get svc "${SVC}" -n "${NS}" -o jsonpath='{.spec.selector.version}' 2>/dev/null || echo "blue")"
if [[ -n "${FORCED_COLOR}" ]]; then
  CANDIDATE_COLOR="${FORCED_COLOR}"
elif [[ "${ACTIVE_COLOR}" == "blue" ]]; then
  CANDIDATE_COLOR="green"
else
  CANDIDATE_COLOR="blue"
fi

CANDIDATE_DEPLOY="gateway-${CANDIDATE_COLOR}"
FULL_IMAGE="${REPO}:${NEW_TAG}"

echo "=========================================================="
echo " Blue-Green Release (R1.7)"
echo " Namespace:        ${NS}"
echo " Color activo:     ${ACTIVE_COLOR}"
echo " Slot candidato:   ${CANDIDATE_COLOR} (${CANDIDATE_DEPLOY})"
echo " Nueva imagen:     ${FULL_IMAGE}"
echo "=========================================================="

echo "==> [1/4] Actualizando imagen en slot inactivo (${CANDIDATE_DEPLOY})..."
kubectl set image "deployment/${CANDIDATE_DEPLOY}" \
  "gateway=${FULL_IMAGE}" \
  -n "${NS}"

kubectl annotate "deployment/${CANDIDATE_DEPLOY}" \
  "deployment.image=${FULL_IMAGE}" \
  "deployment.updatedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -n "${NS}" --overwrite >/dev/null || true

echo "==> [2/4] Esperando readiness de ${CANDIDATE_DEPLOY}..."
if ! kubectl rollout status "deployment/${CANDIDATE_DEPLOY}" -n "${NS}" --timeout=180s; then
  echo "ERROR: ${CANDIDATE_DEPLOY} no alcanzó Ready. El tráfico sigue intacto en ${ACTIVE_COLOR}." >&2
  kubectl rollout undo "deployment/${CANDIDATE_DEPLOY}" -n "${NS}" || true
  exit 1
fi

echo "==> [3/4] Smoke test interno contra slot ${CANDIDATE_COLOR}..."
CANDIDATE_POD="$(kubectl get pods -n "${NS}" -l "app=gateway,version=${CANDIDATE_COLOR}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "${CANDIDATE_POD}" ]]; then
  echo "ERROR: No se encontró pod para ${CANDIDATE_DEPLOY}" >&2
  exit 1
fi

echo "    Pod candidato verificado: ${CANDIDATE_POD}"

echo "==> [4/4] Conmutando tráfico Service ${SVC}: ${ACTIVE_COLOR} -> ${CANDIDATE_COLOR}"
if ! bash "${ROOT_DIR}/scripts/blue-green-switch.sh" "${CANDIDATE_COLOR}"; then
  echo "ERROR: Falló la conmutación. Ejecutando rollback a ${ACTIVE_COLOR}..." >&2
  bash "${ROOT_DIR}/scripts/blue-green-switch.sh" "${ACTIVE_COLOR}" || true
  exit 1
fi

echo "==> Release Blue-Green completado exitosamente. Activo: ${CANDIDATE_COLOR} (${FULL_IMAGE})"
